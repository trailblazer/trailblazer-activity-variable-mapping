require "test_helper"

class NormalizerTest < Minitest::Spec
  # Background of this test is, we need a lower-level interface in eg Macro::Each to create
  # in and out nodes on the Pipeline level.
  it "we want an interface to create In/Out tW nodes but via the DSL" do
    def convert_dsl_to_nodes(lib_ctx, flow_options, signal, injects:, ins:, outs:, default_ctx_for_input:, default_ctx_for_output:, exec_context:, **)
      in_node = Input.convert_tuples_to_node(injects + ins, add_default_ctx: default_ctx_for_input, exec_context_for_provider: exec_context)
      out_node = Output.convert_tuples_to_node(outs, add_default_ctx: default_ctx_for_output, exec_context_for_provider: exec_context)

      return lib_ctx.merge(node_for_input: in_node, node_for_output: out_node), flow_options, signal
    end

    dsl = Trailblazer::Activity::VariableMapping::DSL

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
end
