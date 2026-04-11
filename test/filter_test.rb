require "test_helper"

class FilterTest < Minitest::Spec
  let(:filter_lib_ctx_options) { {aggregate: {}} }

  StepInterface = Trailblazer::Circuit::Task::Adapter::StepInterface

  Filter = Trailblazer::Activity::VariableMapping::Runtime::Filter

  it "read a variable from the {application_ctx}, like In() => {:slug => :my_slug}" do
    my_node = Filter.build_node(
      id: nil,
      args_for_provider: [:read_variable_from_application_ctx],
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
      id: nil,
      args_for_provider: [my_input_provider],
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
# FIXME: remove write_name where it's nil
    my_node = Filter.build_node(
      id: nil,
      args_for_provider: [:downcase_slug, StepInterface::InstanceMethod, merge_to_lib_ctx: {exec_context: my_exec_context}],
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
      id: nil,
      args_for_provider: [my_input_provider, StepInterface],
      write_name: nil, # FIXME.
      read_name: nil,
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, flow_options: original_flow_options = {application_ctx: {slug: "generator-1"}}.freeze,
      **filter_lib_ctx_options

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}}
    assert_equal flow_options, original_flow_options
  end

  describe "Out" do
    it "Out(pass_outer_ctx: true)" do
      my_input_provider = ->(ctx, outer_ctx:, **kws) { [outer_ctx[:params][:id], kws] }

      my_node = Filter.build_node(
        id: nil,
        args_for_provider: [my_input_provider],
        write_name: :my_slug,
        read_name: nil,
        # adds: [Filter::Build::WRAP_VALUE_WITH_HASH], # FIXME: this is for Filter level, then we also have step_block on the Step level.
      )

      my_node = Trailblazer::Circuit::Node::Patch.(
        my_node,
        [:invoke_provider],
        adds: [
          [
            :merge_outer_ctx,
            Trailblazer::Circuit::Node[:merge_outer_ctx, Filter.method(:merge_outer_ctx), Trailblazer::Circuit::Task::Adapter::LibInterface],
            :before, :invoke_provider
          ]
        ]
      )

      my_node = Trailblazer::Circuit::Node::Patch.(
        my_node,
        [],
        adds: [
          Filter::Build::WRAP_VALUE_WITH_HASH
        ]
      )

      # raise "adds vs step_block?"

      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
        **filter_lib_ctx_options,
        original_application_ctx: {params: {id: 1}}, # this is what the Out filter sees as the "outer_ctx".
        flow_options: {application_ctx: {bogus: true, slug: "0x666"}} # this is the ctx produced by the call_task.

      assert_equal lib_ctx, {
        aggregate: {
          :my_slug => [
            1,
            { # the kwargs we see in the user provider:
              bogus: true,
              slug: "0x666",
            }
          ],
        },
        original_application_ctx: {:params=>{:id=>1}}

      }
      assert_equal flow_options, {application_ctx: {bogus: true, slug: "0x666"}}
    end
  end

  describe "Inject" do
    it "writes value to aggregate if it's present (Conditioned)" do
      my_node = Filter::Conditioned.build_node(
        id: nil,
        args_for_provider: [nil], # FIXME: we don't need this here.
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

  it "defaults value if absent, and reads value otherwise (Defaulted)" do
    my_provider_for_default = ->(ctx, params:, **) { params[:id] }

    my_node = Filter::Defaulted.build_node(
      id: nil,default_provider: my_provider_for_default, read_name: :global_id, write_name: :my_global_id,
      args_for_provider: [nil] # FIXME: remove!
    )


    my_ctx = {global_id: 1}
    # raise "how do we get variable_present_in_application_ctx?'s Left to point to the defaulting step?"
    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
      flow_options: original_flow_options = {application_ctx: my_ctx}.freeze,
        **filter_lib_ctx_options,
        terminus: nil

    assert_equal lib_ctx, {:aggregate=>{:my_global_id=>1}}

    my_ctx = {params: {id: 2}}
    # in this run, we let the defaulting logic kick in.
    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
      flow_options: original_flow_options = {application_ctx: my_ctx}.freeze,
        **filter_lib_ctx_options,
        terminus: nil

    assert_equal lib_ctx, {:aggregate=>{:my_global_id=>2}}
  end
end
