require "test_helper"

class FilterTest < Minitest::Spec
  let(:filter_lib_ctx_options) { {aggregate: {}} }

  StepInterface = Trailblazer::Circuit::Task::Adapter::StepInterface

  Filter = Trailblazer::Activity::VariableMapping::Runtime::Filter

  it "read a variable from the {application_ctx}, like In() => {:slug => :my_slug}" do
    my_node = Filter.build_node(
      id: nil,
      args_for_step_build: [:read_variable_from_application_ctx, {}],
      read_name: :slug,
      write_name: :my_slug,
    )

    my_node = Trailblazer::Circuit::Node::Patch.(
      my_node,
      [],
      adds: [
        Trailblazer::Activity::VariableMapping::Runtime::Filter::Build::WRAP_VALUE_WITH_HASH
      ]
    )

    lib_ctx, flow_options, signal = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
      **filter_lib_ctx_options,
      use_application_ctx: false, # TODO: remove.
      terminus: {:my_slug=>"generator-1"} # DISCUSS: value-on-signal

    assert_equal lib_ctx, {aggregate: {:my_slug=>"generator-1"}, target_ctx: original_target_ctx}
    assert_equal flow_options, {}
  end

  it "invoke a callable, wrap its value with a hash" do
    my_input_provider = ->(ctx, slug:, **) { slug.upcase }

    my_node = Filter.build_node(
      id: nil,
      args_for_step_build: [my_input_provider, {}],
      write_name: :my_slug,
    )

    my_node = Trailblazer::Circuit::Node::Patch.(
      my_node,
      [],
      adds: [
        Trailblazer::Activity::VariableMapping::Runtime::Filter::Build::WRAP_VALUE_WITH_HASH
      ]
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
      **filter_lib_ctx_options,
      use_application_ctx: false, # TODO: remove.
      terminus: {:my_slug=>"GENERATOR-1"}

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}, target_ctx: original_target_ctx}
    assert_equal flow_options, {}
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
      args_for_step_build: [:downcase_slug, exec_context: my_exec_context],
      read_name: nil,
      write_name: :my_slug,
    )

    my_node = Trailblazer::Circuit::Node::Patch.(
      my_node,
      [],
      adds: [
        Trailblazer::Activity::VariableMapping::Runtime::Filter::Build::WRAP_VALUE_WITH_HASH
      ]
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
      **filter_lib_ctx_options,
      use_application_ctx: false, # TODO: remove.
      terminus: {:my_slug=>"GENERATOR-1"}

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}, target_ctx: original_target_ctx}
    assert_equal flow_options, {}
  end

  it "invoke a callable, no wrapping" do
    my_input_provider = ->(ctx, slug:, **) { {my_slug: slug.upcase} }

    my_node = Filter.build_node(
      id: nil,
      args_for_step_build: [my_input_provider, {}],
    )

    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
      **filter_lib_ctx_options,
      use_application_ctx: false, # TODO: remove.
      terminus: {:my_slug=>"GENERATOR-1"}

    assert_equal lib_ctx, {aggregate: {:my_slug=>"GENERATOR-1"}, target_ctx: original_target_ctx}
    assert_equal flow_options, {}
  end

  describe "Out" do
    it "Out(pass_outer_ctx: true)" do
      my_input_provider = ->(ctx, outer_ctx:, **kws) { [outer_ctx[:params][:id], kws] }

      my_node = Filter.build_node(
        id: nil,
        args_for_step_build: [my_input_provider, {}],
        write_name: :my_slug,
        # adds: [Filter::Build::WRAP_VALUE_WITH_HASH], # FIXME: this is for Filter level, then we also have step_block on the Step level.
      )

      my_node = Trailblazer::Circuit::Node::Patch.(
        my_node,
        [:invoke_provider],
        adds: [
          [
            :merge_outer_ctx,
            Trailblazer::Circuit::Node[:merge_outer_ctx, Filter.method(:merge_outer_ctx), Trailblazer::Circuit::Task::Adapter::LibInterface],
            :before, :invoke_provider,
            # inbound_signal: nil # we want to sit between {set_target_ctx} and {invoke_provider}.
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

      # FIXME: allow merge_to_circuit_options and merge_to_lib_ctx (Scoped) node feature in one node!
      my_original_node_circuit = Trailblazer::Circuit::Builder.Pipeline(
        [:actual_out_logic, node: my_node]
      )
      my_node = Trailblazer::Circuit::Node::Scoped[:FIXME_scope_for_outer_ctx_merge, my_original_node_circuit, Trailblazer::Circuit::Processor, copy_to_outer_ctx: [:aggregate]]

      # raise "adds vs step_block?"

      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
        **filter_lib_ctx_options,
        use_application_ctx: false, # TODO: remove.
        original_application_ctx: {params: {id: 1}}, # this is what the Out filter sees as the "outer_ctx".
        target_ctx: original_target_ctx = {bogus: true, slug: "0x666"}.freeze, # this is the ctx produced by the call_task.
        terminus: expected_aggregate = {
          :my_slug => [
            1,
            { # the kwargs we see in the user provider:
              bogus: true,
              slug: "0x666",
            }
          ],
        }


      assert_equal lib_ctx, {
        aggregate: expected_aggregate,
        original_application_ctx: {:params=>{:id=>1}},
        target_ctx: original_target_ctx # Note that we don't see {:outer_ctx} here. that's because we Scope the MergeToCircuitOptions node (WIP).

      }
      assert_equal flow_options, {}
    end
  end

  describe "Inject" do
    it "writes value to aggregate if it's present (Conditioned)" do
      my_node = Filter::Conditioned.build_node(
        id: nil,
        args_for_step_build: [nil], # FIXME: we don't need this here.
        write_name: :slug,
        read_name: :slug,
      )

      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
        **filter_lib_ctx_options,
        use_application_ctx: false, # FIXME: remove.
        terminus: {:slug=>"generator-1"},
        signal: Object

      assert_equal lib_ctx, {aggregate: {:slug=>"generator-1"}, target_ctx: original_target_ctx} # we could read {:slug}.
      assert_equal flow_options, {}
    end

    it "works even if the incoming signal is something other than {nil}" do
      my_node = Filter::Conditioned.build_node(
        id: nil,
        write_name: :slug,
        read_name: :slug,
      )

      lib_ctx, flow_options = assert_run my_node, seq: nil, node: true, target_ctx: original_target_ctx = {slug: "generator-1"}.freeze,
        **filter_lib_ctx_options,
        use_application_ctx: false, # FIXME: remove.
        terminus: {:slug=>"generator-1"} # DISCUSS: scoping?

      assert_equal lib_ctx, {aggregate: {:slug=>"generator-1"}, target_ctx: original_target_ctx} # we could read {:slug}.
      assert_equal flow_options, {}
    end

    it "Conditioned always uses the same circuit" do
      skip
      require "benchmark/memory"

      Benchmark.memory do |x|
        x.report("rebuild") do
          my_node = Filter::Conditioned.build_node(
            id: nil,
            write_name: :slug,
            read_name: :slug,
          )

          my_node_2 = Filter::Conditioned.build_node(
            id: nil,
            write_name: :slug,
            read_name: :slug,
          )
        end

        x.compare!
      end

      raise
    end
  end

  it "defaults value if absent, and reads value otherwise (Defaulted)" do
    my_provider_for_default = ->(ctx, params:, **) { params[:id] }

    my_node = Filter::Defaulted.build_node(
      id: nil,
      default_provider: my_provider_for_default,
      read_name: :global_id,
      write_name: :my_global_id,
      # args_for_step_build: [nil] # FIXME: remove!
    )


    my_ctx = {global_id: 1}.freeze
    # raise "how do we get variable_present_in_application_ctx?'s Left to point to the defaulting step?"
    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
      target_ctx: original_target_ctx = my_ctx,
        **filter_lib_ctx_options,
        use_application_ctx: false, # FIXME: remove.
        terminus: {my_global_id: 1}

    assert_equal lib_ctx, {:aggregate=>{:my_global_id=>1}, target_ctx: my_ctx}

    my_ctx = {params: {id: 2}}
    # in this run, we let the defaulting logic kick in.
    lib_ctx, flow_options = assert_run my_node, seq: nil, node: true,
      target_ctx: original_target_ctx = my_ctx,
        **filter_lib_ctx_options,
        use_application_ctx: false, # FIXME: remove.
        terminus: {my_global_id: 2}

    assert_equal lib_ctx, {:aggregate=>{:my_global_id=>2}, target_ctx: my_ctx}
  end
end
