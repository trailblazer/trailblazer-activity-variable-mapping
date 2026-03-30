module Trailblazer
  class Activity
    module VariableMapping
      module Runtime
        class Filter < Struct.new(:read_name, :write_name)
          DEFAULT_STEPS =
          # This Node represents one step in the input/output pipe,
          # one filter.
          def self.build_node(args_for_provider:, read_name:, write_name:, adds: [], builder: Circuit::Builder::Pipeline, steps: nil, **options)
            steps ||= [ # FIXME: better defaulting, please, not very obvious.
              [:invoke_provider, *args_for_provider], # works on flow_options[:application_ctx]
              [:add_value_to_aggregate, :add_value_to_aggregate, Circuit::Task::Adapter::LibInterface::InstanceMethod],
            ]

            pipe = build_circuit(builder: builder, steps: steps, **options)

            create_node_for(pipe, adds: adds, write_name: write_name, read_name: read_name)
          end

          def self.build_circuit(builder:, steps:)
            # usually results in Circuit::Build.Pipeline(...)
            pipe = builder.(
              *steps
            )# FIXME: make me a "template" that is created once at compile-time.
          end

          def self.create_node_for(circuit, adds:, write_name:, read_name:)
            filter_exec_context = Filter[read_name, write_name] # NOTE: this is the key to understanding how state is transported in this little pipeline.

            pipe = Circuit::Adds.(circuit, *adds)

            Circuit::Node::Scoped[:"in.#{write_name}", pipe, Circuit::Processor,
              merge_to_lib_ctx: {exec_context: filter_exec_context},
              copy_to_outer_ctx: [:aggregate],
            ]
          end

          class Conditioned < Filter
            def self.build_circuit(**)
              circuit_steps = [
                [:variable_present_in_application_ctx?, :variable_present_in_application_ctx?, Circuit::Task::Adapter::LibInterface::InstanceMethod,
                  connections: {nil => :invoke_provider, Left => nil}], # Left means terminate.
                [:invoke_provider, :read_variable_from_application_ctx, Circuit::Task::Adapter::StepInterface::InstanceMethod, # extract a value
                  connections: {nil => :wrap_value_with_hash}],
                [:wrap_value_with_hash, :wrap_value_with_hash, Circuit::Task::Adapter::LibInterface::InstanceMethod,
                  connections: {nil => :add_value_to_aggregate}],
                [:add_value_to_aggregate, :add_value_to_aggregate, Circuit::Task::Adapter::LibInterface::InstanceMethod] # terminus.
              ]

              Circuit::Builder::Circuit.(*circuit_steps)
            end
          end

          class Defaulted < Filter
            def self.build_circuit(default_provider:, **options)
              # FIXME: playing with "inheritance" here
              conditioned_circuit = Conditioned.build_circuit

              adds_instruction = [
                Circuit::Node[:invoke_default_provider, default_provider, Circuit::Task::Adapter::StepInterface],
                :after, :variable_present_in_application_ctx?,
                inbound_signal: Left,
                outbound_connections: {nil => :wrap_value_with_hash},
              ]

              Circuit::Adds.(conditioned_circuit, adds_instruction)
            end
          end

          def add_value_to_aggregate(lib_ctx, flow_options, signal, value:, aggregate:, **)
            lib_ctx[:aggregate] = aggregate.merge(value)

            return lib_ctx, flow_options, signal
          end

          def wrap_value_with_hash(lib_ctx, flow_options, signal, value:, **)
            lib_ctx[:value] = {write_name => value}

            return lib_ctx, flow_options, signal
          end

          module Build # TODO: rename to Feature.
            WRAP_VALUE_WITH_HASH = [Trailblazer::Circuit::Node[:wrap_value_with_hash, :wrap_value_with_hash, Circuit::Task::Adapter::LibInterface::InstanceMethod], :after, :invoke_provider]
          end

          # DISCUSS: should we keep the following methods in a subclass of {Filter}?

          # Grab @variable_name from {ctx}.
          # Note that this is called with the StepInterface, since we want to read from application_ctx.
          def read_variable_from_application_ctx(ctx, **)
            return ctx[read_name]
          end

          def variable_present_in_application_ctx?(lib_ctx, flow_options, signal, **)
            application_ctx = flow_options.fetch(:application_ctx) # FIXME: redundant with Adapter::StepInterface.

            signal = application_ctx.key?(read_name) ? signal : Activity::Left

            return lib_ctx, flow_options, signal
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
