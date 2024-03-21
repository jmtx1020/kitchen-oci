# frozen_string_literal: true

# Author:: Justin Steele (<justin.steele@oracle.com>)
#
# Copyright (C) 2024, Stephen Pearson
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Kitchen
  module Driver
    class Oci
      # generic class for blockstorage
      class Blockstorage < Oci
        require_relative "api"
        require_relative "config"
        require_relative "models/iscsi"
        require_relative "models/paravirtual"

        attr_accessor :config, :state, :oci, :api, :volume_state, :volume_attachment_state

        def initialize(config, state, oci, api, action = :create)
          super()
          @config = config
          @state = state
          @oci = oci
          @api = api
          @volume_state = {}
          @volume_attachment_state = {}
          oci.compartment if action == :create
        end

        def create_volume(volume)
          info("Creating <#{volume[:name]}>...")
          result = api.blockstorage.create_volume(volume_details(volume))
          response = volume_response(result.data.id)
          info("Finished creating <#{volume[:name]}>.")
          [response, final_state(response)]
        end

        def attach_volume(volume_details, server_id)
          info("Attaching <#{volume_details.display_name}>...")
          attach_volume = api.compute.attach_volume(attachment_details(volume_details, server_id))
          response = attachment_response(attach_volume.data.id)
          info("Finished attaching <#{volume_details.display_name}>.")
          final_state(response)
        end

        def volume_response(volume_id)
          api.blockstorage.get_volume(volume_id)
            .wait_until(:lifecycle_state, OCI::Core::Models::Volume::LIFECYCLE_STATE_AVAILABLE).data
        end

        def attachment_response(attachment_id)
          api.compute.get_volume_attachment(attachment_id)
            .wait_until(:lifecycle_state, OCI::Core::Models::VolumeAttachment::LIFECYCLE_STATE_ATTACHED).data
        end

        def volume_details(volume)
          OCI::Core::Models::CreateVolumeDetails.new(
            compartment_id: oci.compartment,
            availability_domain: config[:availability_domain],
            display_name: volume[:name],
            size_in_gbs: volume[:size_in_gbs],
            vpus_per_gb: volume[:vpus_per_gb] || 10
          )
        end

        def detatch_and_delete
          state[:volume_attachments].each do |att|
            detatch_volume(att)
          end

          state[:volumes].each do |vol|
            delete_volume(vol)
          end
        end

        def final_state(response)
          case response
          when OCI::Core::Models::Volume
            final_volume_state(response)
          when OCI::Core::Models::VolumeAttachment
            final_volume_attachment_state(response)
          end
        end

        private

        def delete_volume(volume)
          info("Deleting <#{volume[:display_name]}>...")
          api.blockstorage.delete_volume(volume[:id])
          api.blockstorage.get_volume(volume[:id])
            .wait_until(:lifecycle_state, OCI::Core::Models::Volume::LIFECYCLE_STATE_TERMINATED)
          info("Finished deleting <#{volume[:display_name]}>.")
        end

        def detatch_volume(volume_attachment)
          info("Detaching <#{attachment_name(volume_attachment)}>...")
          api.compute.detach_volume(volume_attachment[:id])
          api.compute.get_volume_attachment(volume_attachment[:id])
            .wait_until(:lifecycle_state, OCI::Core::Models::VolumeAttachment::LIFECYCLE_STATE_DETACHED)
          info("Finished detaching <#{attachment_name(volume_attachment)}>.")
        end

        def attachment_name(attachment)
          attachment[:display_name].gsub(/(?:paravirtual|iscsi)-/, "")
        end

        def final_volume_state(response)
          volume_state.store(:id, response.id)
          volume_state.store(:display_name, response.display_name)
          volume_state
        end
      end
    end
  end
end
