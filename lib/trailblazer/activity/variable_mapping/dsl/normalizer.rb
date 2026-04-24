module Trailblazer
  class Activity
    module VariableMapping
      module DSL
        module Normalizer
          module_function

          def call(lib_ctx, *args, **options)
            is_filtered, *args_for_node_create = disect_input_and_output(lib_ctx, *args, **options)

            return lib_ctx, *args unless is_filtered

            node_for_input, node_for_output = create_input_and_output_node(*args_for_node_create)

            lib_ctx, *args = add_task_wrap_extensions(node_for_input, node_for_output, lib_ctx, *args, **options)

            return lib_ctx, *args
          end

          # @private
          def disect_input_and_output(lib_ctx, *args, user_options:, **)
            injects = user_options.find_all { |k, v| k.is_a?(Inject) }
            ins     = user_options.find_all { |k, v| k.is_a?(In) }
            outs    = user_options.find_all { |k, v| k.is_a?(Out) }

            is_filtered = injects.any? || ins.any? || outs.any?

            default_ctx_for_input  = ins.empty? # for Inject() only, or no In()s at all, pass in the default ctx (all variables from outside).
            default_ctx_for_output = outs.empty?

            return is_filtered, injects, ins, outs, default_ctx_for_input, default_ctx_for_output
          end

          # @private
          def create_input_and_output_node(injects, ins, outs, add_default_ctx_for_input, add_default_ctx_for_output)
            return Input.node_for_tuples(injects + ins, add_default_ctx: add_default_ctx_for_input),
              Output.node_for_tuples(outs, add_default_ctx: add_default_ctx_for_input)
          end

          # DISCUSS: the DSL maintains the concept of {:task_wrap_extensions}.
          #          that's why I name it {:adds_for_task_wrap} for now.
          def add_task_wrap_extensions(node_for_input, node_for_output, lib_ctx, *args, adds_for_task_wrap:, **options) # DISCUSS: signature is not ideal, yet.
            # DISCUSS: currently, a tw extension is ADDS instructions?
            vm_extensions = [
              [
                node_for_input,
                :before, :"task_wrap.call_task",
              ],
              [
                node_for_output,
                :after, :"task_wrap.call_task",
              ]
            ]

            return lib_ctx.merge(adds_for_task_wrap: adds_for_task_wrap + vm_extensions), *args
          end
        end
      end
    end
  end
end
