# Gravity SDOH Coordination Platform Client Reference Implementation

This is a reference implementation for the Coordination Platform (CP) system as
defined in the [Gravity SDOHCC Implementation
Guide](http://hl7.org/fhir/us/sdoh-clinicalcare/CapabilityStatement-SDOHCC-CoordinationPlatform.html)

CPs are intermediaries who take on responsibility for managing SDOH referrals
and ensuring they are executed by appropriate service delivery organizations.
These systems must respond to referral fulfillment Tasks received from [Clinical
Care Referral
Sources](http://hl7.org/fhir/us/sdoh-clinicalcare/CapabilityStatement-SDOHCC-ReferralSource.html)
(e.g. EHRs) and also the initiation and management of referral fulfillment Tasks
subsequently directed out to [Referral
Recipients](http://hl7.org/fhir/us/sdoh-clinicalcare/CapabilityStatement-SDOHCC-ReferralRecipient.html)
(CBO).

## Setup
This application is built with Ruby on Rails. To run it locally, first [install
rails](https://guides.rubyonrails.org/getting_started.html#creating-a-new-rails-project-installing-rails).

* Clone this repository: `git clone
  https://github.com/Gravity-SDOHCC/sdoh_referral_source_client.git`
* Navigate to the root of this repository: `cd sdoh_referral_source_client`
* Install dependencios: `bundle install`
* Set up the database: `bundle exec rake db:setup`
* Run the application: `bundle exec rails s`
  * If you need to run the application on a different port, specify the `PORT`
    environment variable: `PORT=3333 bundle exec rails s`
* Navigate to `http://localhost:3000` in your browser

## Running with Docker
A `docker-compose.yml` is provided for running the application in a container:

```
docker compose up -d --build
docker compose logs -f app
```

The application is served on `http://localhost:3000`.

**A code change requires `--build`.** The compose file defines no bind mount, and the
`Dockerfile` copies the source in and precompiles assets at image build time. Editing a
file on disk therefore has no effect on a running container until the image is rebuilt:

```
docker compose up -d --build
```

To publish the application on a different host port without modifying the tracked compose
file, create an untracked `docker-compose.override.yml` next to it. Compose reads it
automatically and it is git-ignored:

```yaml
services:
  app:
    ports: !override
      - "3001:3000"
```

## Usage
See [the usage
documentation](https://github.com/Gravity-SDOHCC/sdoh_referral_source_client/blob/master/docs/usage.md)
for instructions on using the reference implementations.

## Known Issues
* Organizations do not show up immediately once they have been added.

## License
Copyright 2023 The MITRE Corporation

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at
```
http://www.apache.org/licenses/LICENSE-2.0
```
Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.

## Trademark Notice

HL7, FHIR and the FHIR [FLAME DESIGN] are the registered trademarks of Health
Level Seven International and their use does not constitute endorsement by HL7.


## Questions and Contributions
Questions about the project can be asked in the [Gravity SDOH stream on the FHIR Zulip Chat](https://chat.fhir.org/#narrow/stream/233957-Gravity-sdoh-cc).

This project welcomes Pull Requests. Any issues identified with the RI should be submitted via the [GitHub issue tracker](https://github.com/Gravity-SDOHCC/sdoh_coordination_platform_client/issues).

As of October 1, 2023, The Lantana Consulting Group is responsible for the management and maintenance of this Reference Implementation.
In addition to posting on FHIR Zulip Chat channel mentioned above you can contact [Corey Spears](mailto:corey.spears@lantanagroup.com) for questions or requests.
