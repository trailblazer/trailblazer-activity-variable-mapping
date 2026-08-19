require "test_helper"

# Here, we test the combined behavior of a filter chain with regards to the {:aggregate} it produces.
# It's still unclear whether i should use only Wrapped filters or if the filter types don't really care.
#
# We test:
#  1. filters in a sequence
#  2. filters receive the target_ctx
#  3. filters can override values from a former filter
#  4. we can change behavior via :add_default_ctx.
#  5. all the above for Input and Output pipe.
#
# NOTE: this is a fully-fledged unit test. here, i want to cover most behavior of the Input and Output pipe,
#       without going through the DSL.
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

  let(:set_a) do
    my_provider = ->(ctx, value_for_a:, **) { value_for_a }

    my_node_b = Trailblazer::Activity::VariableMapping::Runtime::Filter::Wrapped.build_node(
      id: nil,
      args_for_step_build: [my_provider, {}],
      write_name: :a,
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
      target_ctx: original_ctx = {slug: "0x666", params: {id: 1}}.freeze,
      signal: Object,
      terminus: Object # the input pipe passes through the outer signal.

    assert_equal lib_ctx.keys, [:target_ctx]
    assert_equal lib_ctx[:target_ctx].decompose, [
      {:my_slug=>"0X666", :model=>1},
      {}
    ]
  end

  it "filters receive the {:target_ctx}" do
    my_filter = ->(ctx, **kws) { [CU.inspect(ctx), CU.inspect(kws)] }

    array_of_filter_rows = [
      [:a,  node: filter(:a, &my_filter) ],
      [:b,  node: filter(:b, &my_filter)],
    ]

    output_node = Trailblazer::Activity::VariableMapping::Build::Input.(array_of_filter_rows, add_default_ctx: false)

    lib_ctx, flow_options = assert_run output_node, node: true, seq: nil,
      # original_target_ctx: {x: 4},
      target_ctx: {from_outside: true}.freeze,
      signal: Object, terminus: Object # the input pipe passes through the outer signal.


    assert_equal lib_ctx.keys, [:target_ctx]
    assert_equal lib_ctx[:target_ctx].class, Trailblazer::Activity::VariableMapping::Context
    assert_equal lib_ctx[:target_ctx].decompose, [
      {:a=>["{:from_outside=>true}", "{:from_outside=>true}"], :b=>["{:from_outside=>true}", "{:from_outside=>true}"]}, {}
    ]
  end

  def filter(write_name, &provider)
    Trailblazer::Activity::VariableMapping::Runtime::Filter::Wrapped.build_node(
      id: nil,
      args_for_step_build: [provider, {}],
      write_name: write_name,
    )
  end

  describe "Build.Output" do
    it "a later filter can override an earlier value" do
      array_of_filter_rows = [
        [:a,  node: filter(:a) { |ctx, value_for_a:, **| value_for_a }],
        [:a1, node: filter(:a) { |ctx, value_for_a:, **| value_for_a + 10 }], # we're overriding {:a}.
        [:b,  node: filter(:b) { |ctx, value_for_b:, **| value_for_b }],
      ]

      output_node = Trailblazer::Activity::VariableMapping::Build::Output.(array_of_filter_rows, add_default_ctx: false)

      lib_ctx, flow_options = assert_run output_node, node: true, seq: nil,
        original_target_ctx: {x: 4},
        target_ctx: Trailblazer::Activity::VariableMapping::Context.new(
            {from_outside: true},
            {
              mutable: "here", # this is dropped as we use {add_default_ctx: false}.
              value_for_a: 1,
              value_for_b: 2
            }.freeze
          ),
          signal: Object, terminus: Object # the input pipe passes through the outer signal.


      assert_equal lib_ctx.keys, [:original_target_ctx, :target_ctx]
      assert_equal lib_ctx.class, Hash
      assert_equal lib_ctx[:target_ctx], {
        x: 4, # original.
        a: 11, # the second filter wins.
        b: 2  # other filter
      }
    end

    it "filters receive the {:target_ctx}" do
      my_filter = ->(ctx, **kws) { [CU.inspect(ctx), CU.inspect(kws)] }

      array_of_filter_rows = [
        [:a,  node: filter(:a, &my_filter) ],
        [:b,  node: filter(:b, &my_filter)],
      ]

      output_node = Trailblazer::Activity::VariableMapping::Build::Output.(array_of_filter_rows, add_default_ctx: false)

      lib_ctx, flow_options = assert_run output_node, node: true, seq: nil,
        original_target_ctx: {x: 4},
        target_ctx: Trailblazer::Activity::VariableMapping::Context.new(
            {from_outside: true},
            {
              mutable: "here",
            }.freeze
          ),
          signal: Object, terminus: Object # the input pipe passes through the outer signal.


      assert_equal lib_ctx.keys, [:original_target_ctx, :target_ctx]
      assert_equal lib_ctx.class, Hash
      assert_equal lib_ctx[:target_ctx], {
        x: 4, # original.
        a: ["#<struct Trailblazer::Activity::VariableMapping::Context shadowed={:from_outside=>true}, mutable={:mutable=>\"here\"}>", "{:from_outside=>true, :mutable=>\"here\"}"],
        :b=>["#<struct Trailblazer::Activity::VariableMapping::Context shadowed={:from_outside=>true}, mutable={:mutable=>\"here\"}>", "{:from_outside=>true, :mutable=>\"here\"}"]
      }
    end

    it "{add_default_ctx: true}" do
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
        target_ctx: Trailblazer::Activity::VariableMapping::Context.new({from_outside: true, params: {id: 1}}, {mutable: "here", slug: "0x666"}.freeze),
        signal: Object,
        terminus: Object # the input pipe passes through the outer signal.

      assert_equal lib_ctx.keys, [:original_target_ctx, :target_ctx]
      assert_equal lib_ctx.class, Hash
      # Merge original_ctx with aggregate and mutable.
      assert_equal lib_ctx[:target_ctx], {:model=>1, :controller=>true, :my_slug=>"0X666", :mutable=>"here", :slug=>"0x666"}
    end

    it "{add_default_ctx: false}" do
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

    it "{add_default_ctx: false} means we want whitelisting, without any Out filter, the ctx won't change" do
      array_of_filter_rows = []

      output_node = Trailblazer::Activity::VariableMapping::Build::Output.(
        array_of_filter_rows,
        add_default_ctx: false # DISCUSS: this means "don't merge the inner_ctx's mutable into the outer"?
      )

      lib_ctx, flow_options = assert_run output_node, node: true, seq: nil,
        original_target_ctx: {x: 4},
        target_ctx: Trailblazer::Activity::VariableMapping::Context.new({from_outside: true}, {mutable: "here"}.freeze),
        signal: Object,
        terminus: Object # the input pipe passes through the outer signal.

      assert_equal lib_ctx.keys, [:original_target_ctx, :target_ctx]
      assert_equal lib_ctx.class, Hash
      assert_equal lib_ctx[:target_ctx], {x: 4}
    end

  end

end
