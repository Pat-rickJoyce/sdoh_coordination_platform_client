# A completed screening instrument attached to a referral through
# Task.input:AdditionalContent.
#
# Ported from the referral source client, which renders the same resource on its
# Social Risk Assessments tab. The receiving side needs the same thing for a
# different reason: a referral target deciding whether to accept needs to read
# what the screening actually said, and "QuestionnaireResponse" on its own says
# nothing.
class QuestionnaireResponse
  include ModelHelper

  attr_reader :id, :fhir_resource, :questionnaire, :status, :authored, :author, :item_count, :answers, :sections

  def initialize(fhir_qr, fhir_client: nil)
    @id = fhir_qr.id
    @fhir_resource = fhir_qr
    remove_client_instances(@fhir_resource)
    @questionnaire = fhir_qr.questionnaire
    @status = fhir_qr.status
    @authored = fhir_qr.authored
    @author = fhir_qr.author&.display || fhir_qr.author&.reference
    @item_count = fhir_qr.item&.count || 0
    @answers = extract_answers(fhir_qr.item)
    @sections = extract_sections(fhir_qr.item)
  end

  def display_questionnaire
    return "SDOH screening" if questionnaire.blank?

    questionnaire.split("/").last&.delete_prefix("SDOHCC-Questionnaire")&.underscore&.humanize || questionnaire
  end

  def display_date
    return "--" if authored.blank?

    Time.zone.parse(authored).strftime("%b %-d, %Y")
  rescue ArgumentError
    authored
  end

  private

  def extract_sections(items)
    sections = Array(items).flat_map do |item|
      child_items = Array(item.item)
      if child_items.present?
        child_sections = extract_sections(child_items)
        answered_children = flatten_answer_items(child_items)
        if answered_children.present? && child_sections.blank?
          [{ title: item.text || item.linkId, answers: answered_children }]
        elsif child_sections.present?
          child_sections
        else
          []
        end
      elsif Array(item.answer).present?
        answers = Array(item.answer).map { |answer| answer_hash(item, answer) }
        [{ title: "Responses", answers: answers }]
      else
        []
      end
    end

    # Collapse consecutive "Responses" sections into a single section
    collapse_response_sections(sections)
  end

  def collapse_response_sections(sections)
    return sections if sections.empty?

    collapsed = []
    response_answers = []

    sections.each do |section|
      if section[:title] == "Responses"
        response_answers.concat(section[:answers])
      else
        # If we have accumulated response answers, add them as a single section
        if response_answers.any?
          collapsed << { title: "Responses", answers: response_answers }
          response_answers = []
        end
        collapsed << section
      end
    end

    # Don't forget any trailing response answers
    if response_answers.any?
      collapsed << { title: "Responses", answers: response_answers }
    end

    collapsed
  end

  def flatten_answer_items(items)
    Array(items).flat_map do |item|
      own_answers = Array(item.answer).map { |answer| answer_hash(item, answer) }
      own_answers + flatten_answer_items(item.item)
    end
  end

  def extract_answers(items)
    Array(items).flat_map do |item|
      child_answers = extract_answers(item.item)
      own_answers = Array(item.answer).map do |answer|
        answer_hash(item, answer)
      end
      own_answers + child_answers
    end
  end

  def answer_hash(item, answer)
    {
      link_id: item.linkId,
      text: item.text,
      value: answer_value(answer),
    }
  end

  def answer_value(answer)
    answer.valueString ||
      answer.valueBoolean ||
      answer.valueInteger ||
      answer.valueDecimal ||
      answer.valueDate ||
      answer.valueDateTime ||
      answer.valueCoding&.display ||
      answer.valueCoding&.code ||
      answer.valueQuantity&.value
  end

end
