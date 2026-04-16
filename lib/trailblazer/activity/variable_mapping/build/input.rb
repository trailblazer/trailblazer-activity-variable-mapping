module Trailblazer
  class Activity
    module VariableMapping
      # TODO: move if this stays.
      module Build # DISCUSS: name this "build" because it's not DSL but part of the "building a runtime structure" process?
        module Input
          module_function
          # ========> DSL basically calls Filter.build_node and then produces the
          #           input_pipe and output_pipe
          #           HOW do we make that customizable so we could add filter circuits or alter them?

          def call(ary_of_filter_rows, id: :"input.node", **options)
            input_pipeline = pipeline_for(ary_of_filter_rows, **options)

            node_for_input(input_pipeline, id: id)
          end

          def node_for_input(pipeline, id:, **)
            Circuit::Node::Scoped[id, pipeline, Circuit::Processor, merge_to_lib_ctx: {aggregate: {}}]
          end

          # Adds the default_ctx step as per option {:add_default_ctx}
          def pipeline_for(ary_of_filter_rows, add_default_ctx: false)
            # No In() or {:input}. Use default ctx, which is the original ctx.
            # When using Inject without In/:input, we also need a {default_input} ctx.
            pipeline_steps = [
              *ary_of_filter_rows, # filters are place before {input.scope}.
              [:"input.scope", Runtime.method(:build_context)], # last step
            ]

            if add_default_ctx
              pipeline_steps = [default_input_ctx_row, *pipeline_steps]
            end

            Circuit::Builder.Pipeline(*pipeline_steps)
          end

          def default_input_ctx_row
            [:"input.default_input", Runtime.method(:default_input_ctx)]
          end
        end # Input
      end
    end
  end
end
