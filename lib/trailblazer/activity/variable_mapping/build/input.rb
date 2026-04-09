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

          def node_for_filters(ary_of_filters, **options)
            initial_pipe_ary = initial_input_pipeline_ary(**options)

            node_for_input(initial_pipe_ary, ary_of_filters)
          end

          def node_for_input(initial_ary, ary_of_filters)
            # raise "remove the dsl logic, pipe_for_composable_input"
            # input_pipe = pipe_for_composable_input(**kwargs)

            Circuit::Node::Scoped[:"input.node", ary_of_filters, Circuit::Processor, merge_to_lib_ctx: {aggregate: {}}]
          end

          # Adds the default_ctx step as per option {:add_default_ctx}
          def initial_input_pipeline_ary(add_default_ctx: false)
            # No In() or {:input}. Use default ctx, which is the original ctx.
            # When using Inject without In/:input, we also need a {default_input} ctx.
            pipeline_steps = [
              [:"input.scope", Runtime.method(:build_context)], # last step
            ]

            if add_default_ctx
              pipeline_steps = [default_input_ctx_config] + pipeline_steps
            end

            pipeline_steps
          end

          def default_input_ctx_config
            [:"input.default_input", Runtime.method(:default_input_ctx)]
          end
        end # Input
      end
    end
  end
end
