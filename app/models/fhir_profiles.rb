# Canonical URLs for the FHIR artifacts this client reads and writes.
#
# Every profile, extension and temporary-code-system URL used anywhere in the
# application is declared here so that a spec change is a one-line edit and so
# that no two call sites can disagree about a canonical URL. Nothing outside
# this module should carry one as a string literal.
#
# SDOH artifacts are from HL7 FHIR Implementation Guide "Social Determinants of
# Health Clinical Care" (hl7.fhir.us.sdoh-clinicalcare), STU 3 continuous build.
module FhirProfiles
  # --- SDOH Clinical Care profiles ---

  # SDOHCC Task For Referral Management
  TASK_FOR_REFERRAL_MANAGEMENT = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-TaskForReferralManagement".freeze
  # SDOHCC Procedure
  PROCEDURE = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-Procedure".freeze

  # The Observation profiles that tell a screening answer apart from an
  # assessment result. Task.input:AdditionalContent.value[x] is
  # Reference(Resource) with no targetProfile, so meta.profile is the only thing
  # that says which of the two an Observation is, and a bare "Observation" badge
  # on both says nothing.
  OBSERVATION_ASSESSMENT = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationAssessment".freeze
  OBSERVATION_SCREENING_RESPONSE = "http://hl7.org/fhir/us/sdoh-clinicalcare/StructureDefinition/SDOHCC-ObservationScreeningResponse".freeze

  # --- External code systems ---

  # SNOMED CT, the system the assessment procedure codes below come from.
  SNOMED_CT_SYSTEM = "http://snomed.info/sct".freeze

  # --- SDOH Clinical Care code system ---

  # SDOHCC CodeSystem Temporary Codes
  TEMPORARY_CODE_SYSTEM = "http://hl7.org/fhir/us/sdoh-clinicalcare/CodeSystem/SDOHCC-CodeSystemTemporaryCodes".freeze

  # The two SDOHCC-CodeSystemTemporaryCodes concepts that discriminate the
  # Task.input and Task.output slices in SDOHCC-TaskForReferralManagement.
  ADDITIONAL_CONTENT_CODE = "additional-content".freeze
  ADDITIONAL_CONTENT_DISPLAY = "Additional Content".freeze
  RESULTING_ACTIVITY_CODE = "resulting-activity".freeze
  RESULTING_ACTIVITY_DISPLAY = "Resulting Activity".freeze

  # SDOHCC-CodeSystemTemporaryCodes concept that SDOHCC-ObservationProgramEnrollmentStatus
  # fixes category[enrollment] to. Task.output:AdditionalContent carries
  # assessments, screening responses, goals, conditions and questionnaire
  # responses as well as enrollment status, so the category is what identifies
  # an enrollment status Observation among them.
  PROGRAM_ENROLLMENT_CATEGORY_CODE = "program-enrollment".freeze
end
