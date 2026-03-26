require "test_helper"

class FilterTest < Minitest::Spec
  let(:filter_lib_ctx_options) { {aggregate: {}} }

  StepInterface = Trailblazer::Circuit::Task::Adapter::StepInterface

  Filter = Trailblazer::Activity::VariableMapping::Runtime::Filter

  it "read a variable from the {application_ctx}, like In() => {:slug => :my_slug}" do
    my_node = Filter.build_node(
      args_for_provider: [:read_variable_from_application_ctx, StepInterface::InstanceMethod],
      read_name: :slug,
      write_name: :my_slug,
      adds: [Filter::Build::WRAP_VALUE_WITH_HASH]
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, flow_options: original_flow_options = {application_ctx: {slug: "generator-1"}}.freeze,
      **filter_lib_ctx_options

    assert_equal lib_ctx, {aggregate: {:my_slug=>"generator-1"}}
    assert_equal flow_options, original_flow_options
  end

  it "invoke a callable, wrap its value with a hash" do
    my_input_provider = ->(ctx, slug:, **) { slug.upcase }

    my_node = Filter.build_node(
      args_for_provider: [my_input_provider, StepInterface],
      write_name: :my_slug,
      read_name: nil,
      adds: [Filter::Build::WRAP_VALUE_WITH_HASH]
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, flow_options: original_flow_options = {application_ctx: {slug: "generator-1"}}.freeze,
      **filter_lib_ctx_options

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}}
    assert_equal flow_options, original_flow_options
  end

  it "invoke an {:instance_method}, wrap the value" do
    my_exec_context = Class.new do
      def downcase_slug(ctx, slug:, **)
        slug.upcase
      end
    end.new

    my_node = Filter.build_node(
      args_for_provider: [:downcase_slug, StepInterface::InstanceMethod, merge_to_lib_ctx: {exec_context: my_exec_context}, copy_to_outer_ctx: [:value]],
      read_name: nil,
      write_name: :my_slug,
      adds: [Filter::Build::WRAP_VALUE_WITH_HASH]
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, flow_options: original_flow_options = {application_ctx: {slug: "generator-1"}}.freeze,
      **filter_lib_ctx_options

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}}
    assert_equal flow_options, original_flow_options
  end

  it "invoke a callable, no wrapping" do
    my_input_provider = ->(ctx, slug:, **) { {my_slug: slug.upcase} }

    my_node = Filter.build_node(
      args_for_provider: [my_input_provider, StepInterface],
      write_name: nil, # FIXME.
      read_name: nil,
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, flow_options: original_flow_options = {application_ctx: {slug: "generator-1"}}.freeze,
      **filter_lib_ctx_options

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}}
    assert_equal flow_options, original_flow_options
  end



  describe "Inject" do
    it "writes value to aggregate if it's present" do
      my_node = Filter::Conditioned.build_node(
        args_for_provider: [:read_variable_from_application_ctx, StepInterface::InstanceMethod],
        write_name: :slug,
        read_name: :slug,
      )

      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, flow_options: original_flow_options = {application_ctx: {slug: "generator-1"}}.freeze,
        **filter_lib_ctx_options

      assert_equal lib_ctx, {aggregate: {:slug=>"generator-1"}} # we could read {:slug}.
      assert_equal flow_options, original_flow_options

      # :slug is absent, we don't set anything.
      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, flow_options: original_flow_options = {application_ctx: {id: 1}}.freeze,
        **filter_lib_ctx_options,
        terminus: Trailblazer::Activity::Left

      assert_equal lib_ctx, {aggregate: {}} # pristine aggregate because of no {:slug} anywhere.
      assert_equal flow_options, original_flow_options
    end
  end
end
# FIXME: move me to {activity}.
module Trailblazer
    class Activity
      Left = Class.new
    end
end
