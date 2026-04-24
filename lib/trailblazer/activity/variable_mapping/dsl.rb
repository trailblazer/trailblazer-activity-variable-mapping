module Trailblazer
  class Activity
    module VariableMapping
      # Code invoked through the normalizer, building runtime structures.
      # Naming
      #   Option: Tuple => user filter
      #   Tuple: #<In ...>
      module DSL

        module Input
          module_function

          # NOTE: this is sitting in DSL because we're processing Tuples here, which is a DSL concept (?).
          def node_for_tuples(tuples, add_default_ctx:, build_class: Build::Input) # at this point, we already know if there are In(), or only Inject().
            # raise tuples.inspect

            # produce an array of [id, #<Filter>] "rows", they make up the input/output pipe.
            filter_rows = tuples.flat_map { |left_tuple, right_option| left_tuple.(right_option) }

            # Create a Pipeline with the filter ary above and some additional behavior (eg merging outer ctx).
            build_class.(filter_rows, add_default_ctx: add_default_ctx) # returns node
          end
        end

        module Output
          extend Input

          module_function

          def node_for_tuples(tuples, add_default_ctx:, build_class: Build::Output)
            super # DISCUSS: use inheritance or delegation or module?
          end
        end

        # Keeps user's DSL configuration for a particular io-pipe step.
        # Implements the interface for the actual I/O code and is DSL code happening in the normalizer.
        # The actual I/O code expects {DSL::In} and {DSL::Out} objects to generate the two io-pipes.
        #
        # If a user needs to inject their own private iop step they can create this data structure with desired values here.
        # This is also the reason why a lot of options computation such as {:with_outer_ctx} happens here and not in the IO code.

        class Tuple # FIXME: Make me a Struct
          def initialize(**options)
            @options = options
          end

          # DISCUSS: this is logic run much later in the DSL compilation
          #          problem here is, we have the "Struct" nature as a real DSL object,
          #          and the DSL conversion nature of this object implemented in #call et al.
          def call(right_options) # FIXME: now I'm mixing DSL and building.

            if right_options.is_a?(Array)
              right_options = right_options.collect { |read_name| [read_name, read_name] }.to_h
            end

            if right_options.is_a?(Hash)
              filter_nodes = right_options.collect do |read_name, write_name|
                build_filter_node_row_for_mapping(read_name: read_name, write_name: write_name)
              end

              return filter_nodes
            end

            # right-hand is a provider: ->(*) { ... }
            [build_filter_node_row_for_provider(right_options, **@options)] # @options is usually {read_name: :slug}
          end

          # In() with "callable"/provider never needs hash wrap.
          def build_filter_node_row_for_provider(provider, id: :"in.#{provider}", **options) # we don't need {write_name} etc here.
            [
              id,
              node: Runtime::Filter.build_node(
                id: id, # DISCUSS: do we want the ID in da node?
                args_for_provider: [provider],
                **options # FIXME: what is this exactly? always :read_name and :write_name?
              ),
            ]
          end

          # TODO: make [:model, :params] one fast filter.
          # implement one mapping a la {:model => :model}.
          def build_filter_node_row_for_mapping(read_name:, write_name:, id: :"in.#{read_name} > #{write_name}")
            node = Runtime::Filter.build_node(
              id:                 id,
              args_for_provider:  [:read_variable_from_application_ctx], # Filter::Runtime#read_variable_from_application_ctx
              read_name:          read_name,
              write_name:         write_name,
            )

            node = Trailblazer::Circuit::Node::Patch.(
              node,
              [],
              adds: [
                Runtime::Filter::Build::WRAP_VALUE_WITH_HASH
              ]
            )

            [id, node: node] # for Pipeline().
          end
          # def to_h
          #   @options
          # end


        end # TODO: test {:insert_args}

        # In, Out and Inject are objects instantiated when using the DSL, for instance {In() => [:model]}.
        #
        # NOTE: do the options processing (such as {:with_outer_ctx}) in the In() method and not in the In object,
        #       as we don't need options once we're in a FiltersBuilder.
        #
        #    also, the sooner we complain about a missing or wrong kwarg, the better. Maybe In() should already verify options?
  # raise "could we add, via the DSL in invoke, add an empty In() that doesn't build anything?"
        class In < Tuple
        end # In

        class Out < In
          class PassOuterCtx < Out
            def call(provider_from_user)
              id, node_hsh = build_filter_node_row_for_provider(provider_from_user, **@options)

              node = node_hsh[:node]
              node = add_merge_outer_ctx_step(node)

              return [
                [id, {node: node}]
              ] # @options is usually {read_name: :slug}
            end

            def add_merge_outer_ctx_step(node) # TODO: simplify?
              _node = Circuit::Node::Patch.(
                node,
                [:invoke_provider],
                adds: [
                  [
                    :merge_outer_ctx,
                    Circuit::Node[:merge_outer_ctx, Runtime::Filter.method(:merge_outer_ctx), Circuit::Task::Adapter::LibInterface],
                    :before, :invoke_provider
                  ]
                ]
              )
            end
          end
        end # Out

        # This class is supposed to hold configuration options for Inject().
        #
        # Inject can be 1. "with condition": only add to aggregate if variable is present in original_ctx.
        #               2. "with condition" and default.
        #               3. override: like 2. with a condition always {false}.
        class Inject < Tuple # FIXME: now I'm mixing DSL and building
          def build_filter_node_row_for_provider(provider, read_name:, write_name: read_name, id: :"inject.#{provider}")
            inject_node = Runtime::Filter::Defaulted.build_node(
              id:                 id,
              args_for_provider:  [:read_variable_from_application_ctx],
              read_name:          read_name,
              write_name:         write_name,
              default_provider:   provider,
            )

            # Inject provider always means we need hash wrap.
            inject_node = self.class.add_wrap_value_step(inject_node)

            return id, {node: inject_node}
          end

          def self.add_wrap_value_step(node)
            node = Trailblazer::Circuit::Node::Patch.(
              node,
              [],
              adds: [
                Trailblazer::Activity::VariableMapping::Runtime::Filter::Build::WRAP_VALUE_WITH_HASH
              ]
            )
          end

          def build_filter_node_row_for_mapping(read_name:, write_name:, id: :"inject.#{read_name} > #{write_name}")
            node = Runtime::Filter::Conditioned.build_node(
              id:                 id,
              read_name:          read_name,
              write_name:         write_name,

              args_for_provider: [nil] # FIXME
            )

            return id, {node: node}
          end

          # Override is an Inject filter that is always called,
          # regardless of the variable presence (just like In).
          class Override < Inject # NOTE: Experimental!
            def call(provider_from_user)
              read_name   = @options.fetch(:read_name)
              write_name  = read_name

              # since "override" means "always invoke provider", we can reuse {In} logic.
              id, node_hsh = In.new().build_filter_node_row_for_provider(provider_from_user, read_name: read_name, write_name: write_name)

              node = Inject.add_wrap_value_step(node_hsh[:node])

              return [
                [id, {node: node}]
              ]
            end
          end
        end # Inject

        def self.In(variable_name = nil, tuple_class = In, **left_user_options)
          tuple_class.new(
            read_name: variable_name, # DISCUSS: we're storing the variable_name here, in In() we never have one.
            **left_user_options,
          )
        end

        # Builder for a DSL Output() object.
        def self.Out(variable_name = nil, pass_outer_ctx: false, tuple_class: Out, **left_user_options)
          tuple_class = Out::PassOuterCtx if pass_outer_ctx # DISCUSS: how would this work with multiple features activated?

          In(variable_name, tuple_class, **left_user_options)
        end

        # Used in the DSL by you.
        # DISCUSS: should we move the options processing and deciding code into the resp. FiltersBuilder?
        def self.Inject(variable_name = nil, override: nil, tuple_class: Inject, **left_user_options)
          tuple_class = Inject::Override if override

          In(variable_name, tuple_class, **left_user_options)
        end
      end
    end
  end
end
