require "trailblazer/activity"

module Trailblazer
  class Activity
    module VariableMapping
    end
  end
end

require "trailblazer/activity/variable_mapping/build/input"
require "trailblazer/activity/variable_mapping/build/output" # DISCUSS: separate file?
require "trailblazer/activity/variable_mapping/dsl"
require "trailblazer/activity/variable_mapping/dsl/normalizer"
require "trailblazer/activity/variable_mapping/runtime"
require "trailblazer/activity/variable_mapping/runtime/filter"
require "trailblazer/activity/variable_mapping/context"
require "trailblazer/activity/variable_mapping/dsl/helper"


module Trailblazer
  class Activity
    module VariableMapping
      TOPOLOGY_BUILD_OPTIONS = {
        helpers: {
          DSL::Helper => [:In, :Out, :Inject]
        },
        adds: [
          [
            :variable_mapping, DSL::Normalizer::Node,
            :before, :normalize_wirings
          ],
        ],
      }
    end
  end
end
