module Trailblazer
  class Activity
    module VariableMapping
      # TODO: move if this stays.
      module Build # DISCUSS: name this "build" because it's not DSL but part of the "building a runtime structure" process?
        module Output
          extend Input

          module_function

          def call(pipeline, id: :"output.node", **)
            super
          end

          # Adds the default_ctx step as per option {:add_default_ctx}
          def pipeline_for(ary_of_filter_rows, add_default_ctx: false)
            pipeline_steps = [
              *ary_of_filter_rows, # filters are place before {input.scope}.
              add_default_ctx ? [:"output.default_output", Runtime.method(:default_output_ctx)] : nil,
              [:"output.merge_with_original", Runtime.method(:merge_aggregate_into_original_ctx)], # last step
            ].compact # TODO: make this a bit easier to understand.

            Circuit::Builder.Pipeline(*pipeline_steps)
          end
        end # Input
      end
    end
  end
end
