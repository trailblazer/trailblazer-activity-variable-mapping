module Trailblazer
  class Activity
    module VariableMapping
      module DSL
        module Normalizer
          module_function

          def build_circuit()
            Circuit::Builder.Circuit(
              [:disect_input_and_output, method(:disect_input_and_output),
                connections: {Left => [nil, Left], Right => [:convert_dsl_to_nodes, Right]}],
              [:convert_dsl_to_nodes, method(:convert_dsl_to_nodes)],
              [:add_task_wrap_extensions, method(:add_task_wrap_extensions)]
            )
          end

          def build_node()
            Circuit::Node::Scoped[:vm_normalizer, build_circuit, Circuit::Processor, copy_to_outer_ctx: [:adds_for_task_wrap]]
          end

          # @private
          def disect_input_and_output(lib_ctx, flow_options, signal, user_options:, **)
            injects = user_options.find_all { |k, v| k.is_a?(Inject) }
            ins     = user_options.find_all { |k, v| k.is_a?(In) }
            outs    = user_options.find_all { |k, v| k.is_a?(Out) }

            is_filtered = injects.any? || ins.any? || outs.any?

            return lib_ctx, flow_options, Left unless is_filtered

            options = {
              default_ctx_for_input:  ins.empty?, # for Inject() only, or no In()s at all, pass in the default ctx (all variables from outside).
              default_ctx_for_output: outs.empty?,
              injects: injects,
              ins: ins,
              outs: outs,
            }

            return lib_ctx.merge(options), flow_options, Right
          end

          # @private
          def convert_dsl_to_nodes(lib_ctx, flow_options, signal, injects:, ins:, outs:, default_ctx_for_input:, default_ctx_for_output:, exec_context_for_provider:, **)
            in_node = Input.convert_tuples_to_node(injects + ins, add_default_ctx: default_ctx_for_input, exec_context_for_provider: exec_context_for_provider)
            out_node = Output.convert_tuples_to_node(outs, add_default_ctx: default_ctx_for_output, exec_context_for_provider: exec_context_for_provider)

            return lib_ctx.merge(node_for_input: in_node, node_for_output: out_node), flow_options, signal
          end

          # DISCUSS: the DSL maintains the concept of {:task_wrap_extensions}.
          #          that's why I name it {:adds_for_task_wrap} for now.
          # @private
          def add_task_wrap_extensions(lib_ctx, flow_options, signal, node_for_input:, node_for_output:, adds_for_task_wrap:, **)
            # DISCUSS: currently, a tw extension is ADDS instructions?
            vm_extensions = [
              [
                :"variable_mapping.input",
                node_for_input,
                :before, :"task_wrap.call_task",
              ],
              [
                :"variable_mapping.output",
                node_for_output,
                :after, :"task_wrap.call_task",
              ]
            ]

            return lib_ctx.merge(adds_for_task_wrap: adds_for_task_wrap + vm_extensions), flow_options, signal
          end
        end
      end
    end
  end
end
