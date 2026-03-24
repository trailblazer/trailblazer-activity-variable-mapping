module Trailblazer
  class Activity
    module VariableMapping
      module Runtime
        class Filter
          def self.build_node(user_filter_args:, write_name:)
            pipe = Circuit::Builder.Pipeline(
              [:invoke_callable, *user_filter_args], # works on flow_options[:application_ctx]
              [:wrap_value_with_hash, Filter.method(:wrap_value_with_hash), merge_to_lib_ctx: {write_name: write_name}, copy_to_outer_ctx: [:value]], # DISCUSS: is it faster to maintain a pipe-wide context that keeps {.write_name}?
              [:add_value_to_aggregate, Filter.method(:add_value_to_aggregate)],
            )

            Circuit::Node::Scoped[:"in.#{write_name}", pipe, Circuit::Processor,
              # merge_to_lib_ctx: {aggregate: {}} # this is done once per input pipe and automatically creates a fresh {lib_ctx[:aggregate]} hash for us!
              copy_to_outer_ctx: [:aggregate],
            ]
          end

          # Lib interface.
          def self.add_value_to_aggregate(lib_ctx, flow_options, signal, value:, aggregate:, **)
            lib_ctx[:aggregate] = aggregate.merge(value)

            return lib_ctx, flow_options, signal
          end

          def self.wrap_value_with_hash(lib_ctx, flow_options, signal, value:, write_name:, **)
            lib_ctx[:value] = {write_name => value}

            return lib_ctx, flow_options, signal
          end
        end
      end
    end # VariableMapping
  end
end


          # In() => :my_model_input
          # my_model_input_pipe = Trailblazer::Activity::Circuit::Builder.Pipeline(
          #   [
          #     :invoke_instance_method,
          #     :my_model_input,
          #     Trailblazer::Activity::Circuit::Task::Adapter::StepInterface::InstanceMethod,
          #     {exec_context: Create.new},
          #     Trailblazer::Activity::Circuit::Node::Scoped,
          #     {copy_to_outer_ctx: [:value]}
          #   ],
          #   [:add_value_to_aggregate, :add_value_to_aggregate],
          # )

          # more_model_input_pipe = Trailblazer::Activity::Circuit::Builder.Pipeline(
          #   [:invoke_callable, Create::MoreModelInput, Trailblazer::Activity::Circuit::Task::Adapter::StepInterface], # FIXME: problem here is, we're writing to lib_ctx[:value]
          #   [:add_value_to_aggregate, :add_value_to_aggregate],
          # )

        #   class MergeVariables < Activity
        #     step :args_for_filter # TODO: rename {#ctx_for_filter}.
        #     pass :call_filter # filter could return an actual {nil} as a value.
        #     pass :wrap_value_with_hash # DISCUSS: if not pass, this fails in Defaulted.
        #     pass :merge_variables_into_aggregate

        #     def self.args_for_filter(ctx, flow_options, _, signal, lib_ctx, **)
        #       lib_ctx[:args_for_filter] = ctx

        #       return ctx, flow_options, signal, lib_ctx
        #     end

        #     def self.wrap_value_with_hash(ctx, flow_options, _, signal, lib_ctx, value:, **)
        #       lib_ctx[:value] = {@write_name => value}

        #       return ctx, flow_options, signal, lib_ctx
        #     end

        #     # def self.call_filter(ctx, filter:, args_for_filter:, **)
        #     def self.call_filter(ctx, flow_options, circuit_options, signal, lib_ctx, args_for_filter:, filter: @filter, **)
        #       _, flow_options, value = filter.(args_for_filter, flow_options, circuit_options)

        #       lib_ctx[:value] = value

        #       return ctx, flow_options, signal, lib_ctx
        #     end

        #     # def self.wrap_value_with_hash(ctx, value:, write_name:, **)

        #     def self.merge_variables_into_aggregate(ctx, flow_options, _, signal, lib_ctx, value:, aggregate:,**)
        #       aggregate = aggregate.merge(value)

        #       return ctx, flow_options, signal, lib_ctx.merge(aggregate: aggregate)
        #     end
        #   end
        # end

