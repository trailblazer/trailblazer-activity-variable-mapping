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

            build_class.(filter_rows, add_default_ctx: add_default_ctx) # returns node
          end

          # def self.hash_for_array(ary)
          #   ary.collect { |name| [name, name] }.to_h
          # end
        end

        module Output
          extend Input

          module_function

          def node_for_tuples(tuples, add_default_ctx:, build_class: Build::Output)
            super # DISCUSS: use inheritance or delegation or module?
          end
        end

# TODO: move to Runtime


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
        end # In

        class Out < In
          # def build_filter_node_row_for_provider(provider, read_name:, write_name: read_name, id: :"out.#{provider}")
          #   my_node = Filter.build_node(
          #     id: nil,
          #     args_for_provider: [my_input_provider],
          #     write_name: :my_slug,
          #     read_name: nil,
          #     # adds: [Filter::Build::WRAP_VALUE_WITH_HASH], # FIXME: this is for Filter level, then we also have step_block on the Step level.
          #   )

          #   my_node = Trailblazer::Circuit::Node::Patch.(
          #     my_node,
          #     [:invoke_provider],
          #     adds: [
          #       [
          #         :merge_outer_ctx,
          #         Trailblazer::Circuit::Node[:merge_outer_ctx, Filter.method(:merge_outer_ctx), Trailblazer::Circuit::Task::Adapter::LibInterface],
          #         :before, :invoke_provider
          #       ]
          #     ]
          #   )

          #   my_node = Trailblazer::Circuit::Node::Patch.(
          #     my_node,
          #     [],
          #     adds: [
          #       Filter::Build::WRAP_VALUE_WITH_HASH
          #     ]
          #   )
          # end
          class PassOuterCtx < Out
            def call(provider_from_user)
              raise provider_from_user.inspect
            end
          end
        end # Out

        # This class is supposed to hold configuration options for Inject().
        #
        # Inject can be 1. "with condition": only add to aggregate if variable is present in original_ctx.
        #               2. "with condition" and default.
        #               3. override: like 2. with a condition always {false}.
        class Inject < In # FIXME: now I'm mixing DSL and building
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

          In(variable_name, Out, **left_user_options)
        end

        # Used in the DSL by you.
        # DISCUSS: should we move the options processing and deciding code into the resp. FiltersBuilder?
        def self.Inject(variable_name = nil, override: nil, tuple_class: Inject, **left_user_options)
          tuple_class = Inject::Override if override

          In(variable_name, tuple_class, **left_user_options)
        end

        # require_relative "runtime/filter_step"
        class Tuple
          module Left # FIXME: new implementation, based on Activity::Railway.
            # Utility methods for translating right-hand options and building filters along with ADDS.
            module Builder


              # Build a set of filters for "automatic" options such as {:params => :outer_params}.
              def self.build_filter_adds_for_hash(user_hash, **options)
                user_hash.collect do |from_name, to_name|
                  options_for_build = yield(options, from_name, to_name)

                  # raise options_for_build.inspect

                  value_producer = Runtime::Filter::ValueProducer::ReadVariableFromApplicationCtx.new(variable_name: from_name)
                  raise "and wrap_value_with_hash"

                  build_filter_step_adds(
                    **options_for_build,
                    value_producer: value_producer,
                  )
                end
              end

              # build a special activity based on {filter_activity}, add all "remaining" options as instance variables.
              def self.build_filter_step_adds(value_producer:,
                # filter_activity:,
                  insert_args:,
                  name:, **options_for_build)

                runtime_filter = Runtime::Filter.build_node(
                  # filter_activity,
                  filter: filter,
                  **options_for_build
                )

                # return [runtime_filter, id: name, *insert_args]
              end

              def self.name_for_filter(name: nil, type:, specifier: [], user_filter: nil, **)
                if user_filter
                  specifier = [user_filter] + specifier # DISCUSS: some more elaborate naming here?
                end

                # [type, specifier].compact.join(".") + "{#{name}}"
                ([type, "{#{name}}"] + specifier).join(" ")
              end
            end

            class In
              # A Builder produces a set of ADDS instructions. Each instruction adds a filter for one or many variables.
              class Builder
                # Invoked from {DSL.call_builder}.
                def self.call(right_option, **options)
                  options = compile_options(right_option, **options)

                  translate_right_option_to_filter_adds(right_option, **options)
                end

                # This is options-compiling specific to the left side type.
                def self.compile_options(right_option, filter: Runtime::Filter, pass_aggregate: false, **options_from_left_option)
                    block_for_filter_step_build = -> {
                      # step :with_outer_ctx, after: :args_for_filter if with_outer_ctx
                      step :pass_aggregate, after: :args_for_filter if pass_aggregate
                    } # FIXME: redundancy.

                    options_from_left_option.merge(
                      filter:             filter,
                      # block_for_filter_step_build: block_for_filter_step_build,
                    )
                end

                def self.translate_right_option_to_filter_adds(right_option, **options)
                  # # In()/Out() => [:current_user]
                  if right_option.is_a?(Array)
                    right_option = Left::Builder.hash_for_array(right_option)
                  end

                  # In()/Out() => {:user => :current_user}
                  if right_option.is_a?(Hash)
                    adds = Left::Builder.build_filter_adds_for_hash(right_option, **options) do |build_adds_options, from_name, to_name|
                      build_adds_options.merge(
                        name:                 Left::Builder.name_for_filter(name: "#{from_name.inspect} > #{to_name.inspect}", **options),
                        write_name:           to_name,
                        read_name:            from_name,
                        wrap_value_with_hash: true,
                      )
                    end

                    return adds
                  end

                  # In()/Out() => ->(*) { snippet }
                  circuit_filter = Activity::Circuit.Step(right_option, binary: false) # signature is right_option(ctx, **ctx)

                  adds_row = Left::Builder.build_filter_step_adds(
                    filter:               circuit_filter,
                    name:                 Left::Builder.name_for_filter(**options, user_filter: right_option), # FIXME: name.
                    wrap_value_with_hash: false,
                    **options
                  )

                  return [adds_row]
                end

              end
            end # In

            class Out
              class Builder < In::Builder
                def self.compile_options(right_option, filter_activity: Runtime::FilterStep::MergeVariables::Output, with_outer_ctx: false, delete: false, read_from_aggregate: false, pass_aggregate: false, **options_from_left_option)

                 filter_activity = Runtime::FilterStep::DeleteFromAggregate if delete

                  # DISCUSS: here, we're using a lot of knowledge about the internals of Runtime::FilterStep in the DSL domain, questionable. let's see.
                  #          because actually we shouldn't know anything about FilterStep and the like here.
                  block_for_filter_step_build = -> {
                    step :with_outer_ctx, after: :args_for_filter if with_outer_ctx
                    step :pass_aggregate, after: :args_for_filter if pass_aggregate
                    step :swap_ctx_with_aggregate, replace: :args_for_filter, id: :args_for_filter if read_from_aggregate
                  }

                  options_from_left_option.merge(
                    filter_activity:             filter_activity,
                    block_for_filter_step_build: block_for_filter_step_build,
                  )
                end
              end
            end

            class Inject
              class Builder < In::Builder
                def self.compile_options(right_option, filter_activity: Runtime::FilterStep::Conditioned, override: false, pass_aggregate: false, **options_from_left_option)
                  block_for_filter_step_build = -> {
                    # step :with_outer_ctx, after: :args_for_filter if with_outer_ctx
                    step :pass_aggregate, after: :args_for_filter if pass_aggregate
                  } # FIXME: redundancy.

                  options_from_left_option.merge(
                    filter_activity:             filter_activity,
                    block_for_filter_step_build: block_for_filter_step_build,
                    override: override, # DISCUSS: do we want to pass that here?
                  )
                end

                def self.translate_right_option_to_filter_adds(right_option, variable_name:, override:, filter_activity:, **options_from_left_option)
                  # # In()/Out() => [:current_user]
                  if right_option.is_a?(Array)
                    right_option = Left::Builder.hash_for_array(right_option)
                  end

                  # In()/Out() => {:user => :current_user}
                  if right_option.is_a?(Hash)
                    adds = Left::Builder.build_filter_adds_for_hash(right_option, **options_from_left_option) do |build_adds_options, from_name, to_name|

                      # FIXME: this is different to In
                      condition = VariablePresent.new(variable_name: to_name)

                      build_adds_options.merge(
                        name:                 Left::Builder.name_for_filter(name: from_name.inspect, **options_from_left_option),
                        write_name:           to_name,
                        read_name:            from_name,
                        wrap_value_with_hash: true,
                        condition: condition,
                        filter_activity: filter_activity,
                      )
                    end

                    return adds
                  end

                  default_filter = Activity::Circuit.Step(right_option, binary: false) # signature is right_option(ctx, **ctx)

                  # TODO: override is MergeVariables with filter: default_filter
                  if override
                    adds_instruction = Left::Builder.build_filter_step_adds(
                      filter_activity:  Runtime::FilterStep::MergeVariables,
                      filter:           default_filter,
                      write_name:       variable_name,
                      name:             Left::Builder.name_for_filter(user_filter: right_option, **options_from_left_option, specifier: ["{override: true}"]),
                      wrap_value_with_hash: true,
                      **options_from_left_option
                    )

                    return [adds_instruction]
                  end

                  # Inject(:variable_name) => ->(*) { snippet }
                  # FIXME: this is different to In
                  condition = VariablePresent.new(variable_name: variable_name)
                  filter = VariableMapping::VariableFromCtx.new(variable_name: variable_name)

                  # Return one ADDS instruction that inserts a particular filter into the In/Out pipeline.
                  adds_instruction = Left::Builder.build_filter_step_adds(
                    filter_activity: Runtime::FilterStep::Defaulted,
                    condition: condition,
                    filter: filter,
                    default_filter: default_filter,
                    write_name: variable_name,
                    name:             Left::Builder.name_for_filter(user_filter: right_option, **options_from_left_option, name: variable_name.inspect, specifier: ["{defaulted: true}"]),
                    wrap_value_with_hash: true,
                    **options_from_left_option,
                  )

                  return [adds_instruction]
                end
              end
            end

          end
        end
      end
    end
  end
end
