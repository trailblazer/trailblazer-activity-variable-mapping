module Trailblazer
  class Activity
    module VariableMapping
      module Runtime
        class Filter < Struct.new(:read_name, :write_name)
          # This Node represents one step in the input/output pipe,
          # one filter.
          def self.build_node(args_for_provider:, read_name:, write_name:, adds: [])
            filter_exec_context = Filter[read_name, write_name] # NOTE: this is the key to understanding how state is transported in this little pipeline.

            pipe_steps = [
              [:invoke_provider, *args_for_provider], # works on flow_options[:application_ctx]
              [:add_value_to_aggregate, :add_value_to_aggregate, Circuit::Task::Adapter::LibInterface::InstanceMethod],
            ]

            pipe = Circuit::Builder.Pipeline(
              *pipe_steps
            )# FIXME: make me a "template" that is created once at compile-time.

            pipe = Circuit::Adds.(pipe, *adds)

            Circuit::Node::Scoped[:"in.#{write_name}", pipe, Circuit::Processor,
              merge_to_lib_ctx: {exec_context: filter_exec_context},
              copy_to_outer_ctx: [:aggregate],
            ]
          end

          def add_value_to_aggregate(lib_ctx, flow_options, signal, value:, aggregate:, **)
            lib_ctx[:aggregate] = aggregate.merge(value)

            return lib_ctx, flow_options, signal
          end

          def wrap_value_with_hash(lib_ctx, flow_options, signal, value:, **)
            lib_ctx[:value] = {write_name => value}

            return lib_ctx, flow_options, signal
          end

          module Build
            WRAP_VALUE_WITH_HASH = [Trailblazer::Circuit::Node[:wrap_value_with_hash, :wrap_value_with_hash, Circuit::Task::Adapter::LibInterface::InstanceMethod], :after, :invoke_provider]
          end

          # DISCUSS: should we keep the following methods in a subclass of {Filter}?

          # Grab @variable_name from {ctx}.
          # Note that this is called with the StepInterface, since we want to read from application_ctx.
          def read_variable_from_application_ctx(ctx, **)
            return ctx[read_name]
          end

          module Provider
          end

          # Filter
          # FIXME: old signature here
          class VariablePresent #< VariableFromCtx
            # Grab @variable_name from {ctx} if it's there.
            def call(ctx, flow_options, _, **) # Circuit-step interface
              # raise
              return ctx, flow_options, ctx.key?(@variable_name)
            end
          end
        end # Filter
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
          #   [:invoke_provider, Create::MoreModelInput, Trailblazer::Activity::Circuit::Task::Adapter::StepInterface], # FIXME: problem here is, we're writing to lib_ctx[:value]
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

