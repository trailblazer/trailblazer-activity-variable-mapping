module Trailblazer
  class Activity
    module VariableMapping

      # Runtime classes

      # These objects are created via the DSL, keep all i/o steps in a Pipeline
      # and run the latter as a taskWrap step.

      module Runtime
        module_function

        # TODO: move to Runtime::Input and :::Output.

        # Merge all original ctx variables into the new input_ctx.
        # This happens when no In() is provided.
        def default_input_ctx(lib_ctx, flow_options, signal, aggregate:, **)
          default_ctx = flow_options[:application_ctx] # DISCUSS: couldn't this be optimized in a way that we simply use the original ctx as the immutable part?

          lib_ctx[:aggregate] = aggregate.merge(default_ctx)

          return lib_ctx, flow_options, signal
        end

        def build_context(lib_ctx, flow_options, signal, aggregate:, **)
          new_application_ctx = Context.new(
            aggregate,
            {}, # mutable variables
            # flow_options[:context_options]
          )

          flow_options = flow_options.merge(application_ctx: new_application_ctx)

          return lib_ctx, flow_options, signal
        end
      end
    end
  end
end
