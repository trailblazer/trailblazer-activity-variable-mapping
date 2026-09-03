require "forwardable"

module Trailblazer
  class Activity
    module VariableMapping
      module DSL
        module Helper
          extend Forwardable
          def_delegators DSL, :In, :Out, :Inject
        end
      end
    end
  end
end
