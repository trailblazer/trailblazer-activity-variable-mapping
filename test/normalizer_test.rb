require "test_helper"

class NormalizerTest < Minitest::Spec
  let(:dsl) { Trailblazer::Activity::VariableMapping::DSL }

  # Background of this test is, we need a lower-level interface in eg Macro::Each to create
  # in and out nodes on the Pipeline level.
  it "we want an interface to create In/Out tW nodes but via the DSL" do
    lib_ctx, _ = Trailblazer::Activity::VariableMapping::DSL::Normalizer.convert_dsl_to_nodes(
      {},
      {},
      nil,
      ins: [[dsl.In(), [:current_user]], [dsl.In(), [:params]]],
      outs: [[dsl.Out(), [:model]]],
      injects: [],
      default_ctx_for_input: false,
      default_ctx_for_output: false,

      exec_context: Object,
    )

    in_node, out_node = lib_ctx[:node_for_input], lib_ctx[:node_for_output]

    # test in
    lib_ctx, _ = assert_run in_node, node: true, seq: nil, target_ctx: {params: 1, current_user: Module, bogus: true}
    assert_equal lib_ctx[:target_ctx].to_h, {:current_user=>Module, :params=>1} # functional test, don't test Context internals here.

    # test out
    lib_ctx, _ = assert_run out_node, node: true, seq: nil, target_ctx: lib_ctx[:target_ctx].merge(pollute: true, model: Class)
    assert_equal lib_ctx[:target_ctx].to_h, {:current_user=>Module, :params=>1, model: Class, bogus: true} # functional test, don't test Context internals here.
  end

    # provider_filter = ->(lib_ctx, flow_options, signal, index:, **) do
    #         return lib_ctx, flow_options, index
    #       end

    #       provider_node = Trailblazer::Circuit::Node[provider_filter, Trailblazer::Circuit::Task::Adapter::LibInterface]

    #       my_custom_filter_with_wrap_hash = Class.new(Trailblazer::Activity::VariableMapping::Runtime::Filter) do
    #         def self.build_circuit(**)
    #           circuit = Trailblazer::Circuit::Adds.(super, Trailblazer::Activity::VariableMapping::Runtime::Filter::Build::WRAP_VALUE_WITH_HASH) # redundant to Override.
    #         end
    #       end

    #       node_for_index = my_custom_filter_with_wrap_hash.build_node(
    #         provider_node: provider_node,
    #         id: :add_index,
    #         write_name: :index
    #       )
  it "we can inject custom filters" do
    # This filter can access {lib_ctx} etc.
    my_custom_filter = ->(lib_ctx, flow_options, signal, aggregate:, index:, **) do
      lib_ctx = lib_ctx.merge(aggregate: aggregate.merge(my_index: index))

      return lib_ctx, flow_options, signal
    end

    my_left_tuple = ->(*) { [[:my_custom_id, my_custom_filter]] }

    lib_ctx, _ = Trailblazer::Activity::VariableMapping::DSL::Normalizer.convert_dsl_to_nodes(
      {},
      {},
      nil,
      ins: [[dsl.In(), [:current_user]], [my_left_tuple]],
      outs: [[dsl.Out(), [:index]]],
      injects: [],
      default_ctx_for_input: false,
      default_ctx_for_output: false,

      exec_context: Object,
    )

    in_node, out_node = lib_ctx[:node_for_input], lib_ctx[:node_for_output]

    # test in
    lib_ctx, _ = assert_run in_node, node: true, seq: nil, target_ctx: {params: 1, current_user: Module, bogus: true},
      aggregate: {}, index: 0
    assert_equal lib_ctx[:target_ctx].to_h, {current_user: Module, my_index: 0} # functional test, don't test Context internals here.

  end
end
