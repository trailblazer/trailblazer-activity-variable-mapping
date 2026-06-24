module Trailblazer
  class Activity
    module VariableMapping
      module Runtime
        class Filter < Struct.new(:read_name, :write_name, keyword_init: true) # We *could* allow more options here.
          # This Node represents one step in the input/output pipe,
          # one filter.
          def self.build_node(id:, **options)
            circuit = build_circuit(**options)

            options_for_filter = options.slice(*members) # extract :read_name, :write_name.

            create_node_for(circuit, id: id, **options_for_filter)
          end

          def self.build_circuit(args_for_step_build:, **options)
            provider_arg, provider_options = args_for_step_build

            provider_node = Activity::Step.build(
              provider_arg,
              **provider_options, # e.g. {exec_context: Filter.new}
              binary: false
            )

            steps = rows_for_build(provider_node)

            Circuit::Builder.Circuit(*steps)
          end

          def self.create_node_for(circuit, id:, **options_for_filter)
            # DISCUSS: In theory, we'd need different Filter subclasses for different filter types, eg a user provider doesn't need any {write_name}.
            filter_exec_context = Filter[**options_for_filter].freeze # NOTE: this is the key to understanding how configuration state is transported in this little pipeline.

            return Circuit::Node::MergeToCircuitOptions[id, circuit, Circuit::Processor, exec_context: filter_exec_context]
          end

          # FIXME: can we reuse nodes?
          def self.rows_for_build(provider_node)
            [
              [:invoke_provider, node: provider_node],
              [:add_value_to_aggregate, :add_value_to_aggregate, Circuit::Task::Adapter::LibInterface::InstanceMethod],
            ]
          end

          module Out

          end

          class Conditioned < Filter
            def self.build_circuit(**options)
              super(**options, args_for_step_build: [:read_variable_from_application_ctx, {}]) # the provider is {#read_variable_from_application_ctx}.
            end

            # FIXME: we can reuse most nodes?
            def self.rows_for_build(provider_node)
              [
                [:variable_present_in_application_ctx?, :variable_present_in_application_ctx?, Circuit::Task::Adapter::LibInterface::InstanceMethod,
                  connections: Circuit::Resolver::Conditional.new([Left], nil, :invoke_provider)], # Left means terminate.
                [:invoke_provider, node: provider_node, # extract a value
                  connections: Circuit::Resolver::Fixed.new(:wrap_value_with_hash)],
                [:wrap_value_with_hash, :wrap_value_with_hash, Circuit::Task::Adapter::LibInterface::InstanceMethod,
                  connections: Circuit::Resolver::Fixed.new(:add_value_to_aggregate)],
                [:add_value_to_aggregate, :add_value_to_aggregate, Circuit::Task::Adapter::LibInterface::InstanceMethod,
                  connections: Circuit::Resolver::Fixed.new(nil) # terminus.
                ]
              ]
            end

            # TODO: save memory by not creating identical circuits!
            # CIRCUIT = build_node(id: :bla)
          end

          class Defaulted < Filter
            def self.build_node(default_provider:, id:, **options)
              # FIXME: playing with "inheritance" here
              conditioned_circuit = Conditioned.build_circuit(**options)

              default_provider_node = Activity::Step.build(default_provider, binary: false)

              adds_instruction = [
                :invoke_default_provider,
                default_provider_node,
                :after, :variable_present_in_application_ctx?,
                inbound_signal: Left,
                resolver: Circuit::Resolver::Fixed.new(:wrap_value_with_hash),
              ]

              circuit = Circuit::Adds.(conditioned_circuit, adds_instruction)

              # FIXME: redundant.
              options_for_filter = options.slice(*members) # extract :read_name, :write_name.

              create_node_for(circuit, id: id, **options_for_filter)
            end
          end

          def add_value_to_aggregate(lib_ctx, flow_options, value, aggregate:, **)
            lib_ctx[:aggregate] = aggregate.merge(value)

            return lib_ctx, flow_options, value
          end

          def wrap_value_with_hash(lib_ctx, flow_options, value, **)
            value = {write_name => value}

            return lib_ctx, flow_options, value
          end

          module Build # TODO: rename to Feature.
            WRAP_VALUE_WITH_HASH = [:wrap_value_with_hash, Circuit::Node[:wrap_value_with_hash, :wrap_value_with_hash, Circuit::Task::Adapter::LibInterface::InstanceMethod], :after, :invoke_provider]
          end

          # DISCUSS: should we keep the following methods in a subclass of {Filter}?

          # Grab @variable_name from {ctx}.
          # Note that this is called with the StepInterface, since we want to read from application_ctx.
          def read_variable_from_application_ctx(ctx, **)
            return ctx[read_name]
          end

          def variable_present_in_application_ctx?(lib_ctx, flow_options, signal, target_ctx:, **)
            signal = target_ctx.key?(read_name) ? signal : Activity::Left

            return lib_ctx, flow_options, signal
          end

          # FIXME: should we use instance method instead?
          def self.merge_outer_ctx(lib_ctx, flow_options, signal, original_application_ctx:, target_ctx:, **)
            target_ctx = target_ctx.merge(outer_ctx: original_application_ctx)

            return lib_ctx.merge(target_ctx: target_ctx), flow_options, signal
          end
        end # Filter
      end
    end # VariableMapping
  end
end
