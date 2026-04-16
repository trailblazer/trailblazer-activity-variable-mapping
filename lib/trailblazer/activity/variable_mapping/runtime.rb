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

          # Lib interface.
  def save_original_application_ctx(lib_ctx, flow_options, signal, **)
    # DISCUSS: do we need this?
    lib_ctx[:original_application_ctx] = flow_options[:application_ctx] # the "outer ctx".

    return lib_ctx, flow_options, signal
  end







          def self.merge_aggregate_into_original_ctx(lib_ctx, flow_options, signal, aggregate:, original_application_ctx:, **)
            new_ctx = original_application_ctx.merge(aggregate)

            flow_options = flow_options.merge(application_ctx: new_ctx)

            return lib_ctx, flow_options, signal
          end

          # Merge the mutable part of the scoped ctx back into the outer ctx.
          # Default behavior when there's nothing configured.
          def self.default_output_ctx(lib_ctx, flow_options, signal, aggregate:, **)
            ctx = flow_options[:application_ctx]

            _wrapped, mutable = ctx.decompose # `_wrapped` is what the `:input` filter returned, `mutable` is what the task wrote to `scoped`.

            lib_ctx[:aggregate] = aggregate.merge(mutable)

            return lib_ctx, flow_options, signal
          end

      end
    end
  end
end
