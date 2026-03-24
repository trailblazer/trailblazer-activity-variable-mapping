require "test_helper"

class FilterTest < Minitest::Spec
  let(:filter_lib_ctx_options) { {aggregate: {}} }

  StepInterface = Trailblazer::Circuit::Task::Adapter::StepInterface


  it "invoke a callable, wrap its value with a hash" do
    my_input_filter = ->(ctx, slug:, **) { slug.upcase }

    my_node = Trailblazer::Activity::VariableMapping::Runtime::Filter.build_node(user_filter_args: [my_input_filter, StepInterface], write_name: :my_slug)

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, flow_options: original_flow_options = {application_ctx: {slug: "generator-1"}}.freeze,
      **filter_lib_ctx_options

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}}
    assert_equal flow_options, original_flow_options
  end

  it "invoke an :instance_method, wrap the value" do
    my_exec_context = Class.new do
      def downcase_slug(ctx, slug:, **)
        slug.upcase
      end
    end.new

    my_node = Trailblazer::Activity::VariableMapping::Runtime::Filter.build_node(
      user_filter_args: [:downcase_slug, StepInterface::InstanceMethod, merge_to_lib_ctx: {exec_context: my_exec_context}, copy_to_outer_ctx: [:value]],
      write_name: :my_slug
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, flow_options: original_flow_options = {application_ctx: {slug: "generator-1"}}.freeze,
      **filter_lib_ctx_options

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}}
    assert_equal flow_options, original_flow_options
  end
end
