require "test_helper"

class TaskWrapPipesTest < Minitest::Spec
  let(:my_node_a) do
    my_input_provider = ->(ctx, slug:, **) { {my_slug: slug.upcase} }

    my_node_a = Trailblazer::Activity::VariableMapping::Runtime::Filter.build_node(
      id: nil,
      args_for_step_build: [my_input_provider, {}],
    )
  end

  let(:my_node_b) do
    my_model_provider = ->(ctx, params:, **) { params[:id] }

    my_node_b = Trailblazer::Activity::VariableMapping::Runtime::Filter::Wrapped.build_node(
      id: nil,
      args_for_step_build: [my_model_provider, {}],
      write_name: :model,
    )
  end

  it "Build.Input with {add_default_ctx: true}" do
    array_of_filter_rows = [
      [:a, node: my_node_a],
      [:b, node: my_node_b],
    ]

    input_node = Trailblazer::Activity::VariableMapping::Build::Input.( # DISCUSS: shouldn't we use {DSL::Input.node_for_tuples} here?
      array_of_filter_rows,
      add_default_ctx: true
    )

    lib_ctx, flow_options = assert_run input_node, node: true,
      use_application_ctx: false, # FIXME: remove.
      target_ctx: original_ctx = {slug: "0x666", params: {id: 1}, seq: []}.freeze,
      signal: Object,
      terminus: Object, seq: [] # the input pipe passes through the outer signal.

    assert_equal lib_ctx.keys, [:target_ctx]
    assert_equal lib_ctx[:target_ctx].decompose, [
      {:slug=>"0x666", :params=>{:id=>1}, :seq=>[], :my_slug=>"0X666", :model=>1},
      {}
    ]
  end

  it "{add_default_ctx: false}" do
    array_of_filter_rows = [
      [:a, node: my_node_a],
      [:b, node: my_node_b],
    ]

    input_node = Trailblazer::Activity::VariableMapping::Build::Input.( # DISCUSS: shouldn't we use {DSL::Input.node_for_tuples} here?
      array_of_filter_rows,
      add_default_ctx: false # only let in defined variables.
    )

    lib_ctx, flow_options = assert_run input_node, node: true, seq: nil,
      use_application_ctx: false, # FIXME: remove.
      target_ctx: original_ctx = {slug: "0x666", params: {id: 1}}.freeze,
      signal: Object,
      terminus: Object # the input pipe passes through the outer signal.

    assert_equal lib_ctx.keys, [:target_ctx]
    assert_equal lib_ctx[:target_ctx].decompose, [
      {:my_slug=>"0X666", :model=>1},
      {}
    ]
  end

  it "Build.Output add_default_ctx: true" do
    array_of_filter_rows = [
      [:a, node: my_node_a],
      [:b, node: my_node_b],
    ]

    output_node = Trailblazer::Activity::VariableMapping::Build::Output.(
      array_of_filter_rows,
      add_default_ctx: true
    )

    lib_ctx, flow_options = assert_run output_node, node: true, seq: nil,
      original_target_ctx: {model: Module, controller: true},
      use_application_ctx: false, # FIXME: remove.
      target_ctx: Trailblazer::Activity::VariableMapping::Context.new({from_outside: true, params: {id: 1}}, {mutable: "here", slug: "0x666"}.freeze),
      signal: Object,
      terminus: Object # the input pipe passes through the outer signal.

    assert_equal lib_ctx.keys, [:original_target_ctx, :target_ctx]
    assert_equal lib_ctx.class, Hash
    # Merge original_ctx with aggregate and mutable.
    assert_equal lib_ctx[:target_ctx], {:model=>1, :controller=>true, :my_slug=>"0X666", :mutable=>"here", :slug=>"0x666"}
  end

  it "Build.Output add_default_ctx: false" do
    array_of_filter_rows = [
      [:a, node: my_node_a],
      [:b, node: my_node_b],
    ]

    output_node = Trailblazer::Activity::VariableMapping::Build::Output.(
      array_of_filter_rows,
      add_default_ctx: false # DISCUSS: this means "don't merge the inner_ctx's mutable into the outer"?
    )

    lib_ctx, flow_options = assert_run output_node, node: true, seq: nil,
      original_target_ctx: {model: Module, params: {}},
      use_application_ctx: false, # FIXME: remove.
      target_ctx: Trailblazer::Activity::VariableMapping::Context.new({from_outside: true, params: {id: 1}}, {mutable: "here", slug: "0x666"}.freeze),
      signal: Object,
      terminus: Object # the input pipe passes through the outer signal.

    assert_equal lib_ctx.keys, [:original_target_ctx, :target_ctx]
    assert_equal lib_ctx.class, Hash
    assert_equal lib_ctx[:target_ctx], {
      :model=>1,          # model is overridden by one Out filter.
      :my_slug=>"0X666",  # the other Out filter provides my_slug
      params: {}, # from the original ctx.
    }
  end

  it "Build.Output {add_default_ctx: false} means we want whitelisting, without any Out filter, the ctx won't change" do
    array_of_filter_rows = []

    output_node = Trailblazer::Activity::VariableMapping::Build::Output.(
      array_of_filter_rows,
      add_default_ctx: false # DISCUSS: this means "don't merge the inner_ctx's mutable into the outer"?
    )

    lib_ctx, flow_options = assert_run output_node, node: true, seq: nil,
      original_target_ctx: {model: Module},
      use_application_ctx: false, # FIXME: remove.
      target_ctx: Trailblazer::Activity::VariableMapping::Context.new({from_outside: true}, {mutable: "here"}.freeze),
      signal: Object,
      terminus: Object # the input pipe passes through the outer signal.

    assert_equal lib_ctx.keys, [:original_target_ctx, :target_ctx]
    assert_equal lib_ctx.class, Hash
    assert_equal lib_ctx[:target_ctx], {model: Module}
  end
end
