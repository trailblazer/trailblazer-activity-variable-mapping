module Trailblazer
  class Activity
    module VariableMapping
      module Runtime
        module_function
        # TODO: move to Runtime::Input and :::Output.

        # Merge all original ctx variables into the new input_ctx.
        # This happens when no In() is provided.
        def default_input_ctx(lib_ctx, flow_options, signal, aggregate:, target_ctx:, **)
          lib_ctx[:aggregate] = aggregate.merge(target_ctx)

          return lib_ctx, flow_options, signal
        end

        def build_context(lib_ctx, flow_options, signal, aggregate:, target_ctx:, **)
          new_target_ctx = Context.new(
            aggregate,
            {}, # mutable variables
            target_ctx # save the original ctx, only visible to us in I/O.
          )

          return lib_ctx.merge(target_ctx: new_target_ctx), flow_options, signal
        end

        # def save_original_target_ctx(lib_ctx, flow_options, signal, target_ctx:, **)
        #   # save the "outer ctx" under {:original_target_ctx}.
        #   lib_ctx = lib_ctx.merge(original_target_ctx: target_ctx)

        #   return lib_ctx, flow_options, signal
        # end

        def merge_aggregate_into_original_ctx(lib_ctx, flow_options, signal, aggregate:, target_ctx:, original_target_ctx: target_ctx.original_ctx, **)
          new_ctx = original_target_ctx.merge(aggregate)

          lib_ctx = lib_ctx.merge(target_ctx: new_ctx)

          return lib_ctx, flow_options, signal
        end

        # Merge the mutable part of the scoped ctx back into the outer ctx.
        # Default behavior when there's nothing configured.
        def default_output_ctx(lib_ctx, flow_options, signal, aggregate:, target_ctx:, **)
          _wrapped, mutable = target_ctx.decompose # `_wrapped` is what the `:input` filter returned, `mutable` is what the task wrote to `scoped`.

          lib_ctx[:aggregate] = aggregate.merge(mutable)

          return lib_ctx, flow_options, signal
        end
      end # Runtime
    end
  end
end
