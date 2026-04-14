require "test_helper"

class ComposableTest < Minitest::Spec
  # Filter = Trailblazer::Activity::VariableMapping::Runtime::Filter

  let(:my_create) do
    Class.new do
      def model(ctx, id:, **)
        raise id.inspect
      end
    end
      .new
  end

  let(:my_flow_options) { {application_ctx: {controller: Object, params: {id: 1}}} }
  let(:my_model_call_task) { Trailblazer::Activity::Step.build(:model, id: :call_task) }

  it "without any i/o, #model throws exception (this tests our fixture)" do
    my_model_tw = Pipeline(
      [:call_task, node: my_model_call_task]
    )

    exception = assert_raises ArgumentError do
      lib_ctx, flow_options = assert_run my_model_tw, exec_context: my_create, seq: [],
        flow_options: my_flow_options
    end

    assert_equal exception.message, %(missing keyword: :id)
  end

  it "i want an input pipe that adds variables to the default_ctx" do
    my_input_provider       = ->(ctx, slug:, **) { slug.upcase }
    my_provider_for_default = ->(ctx, params:, **) { params[:id] }


    # this comes straight outta DSL.
    # see #pipe_for_composable_input
    # this vvv should be done by the DSL? yes.
    # i refrain from allowing Adds, we just add the steps in that order.

    my_input_node = Trailblazer::Activity::VariableMapping::Runtime::Filter.build_node(
      id: :"in.slug",
      args_for_provider: [my_input_provider],
      write_name: :my_slug,
      read_name: nil,
      # adds: [Trailblazer::Activity::VariableMapping::Runtime::Filter::Build::WRAP_VALUE_WITH_HASH]
    )
    my_input_node = Trailblazer::Circuit::Node::Patch.(
      my_input_node,
      [],
      adds: [
        Trailblazer::Activity::VariableMapping::Runtime::Filter::Build::WRAP_VALUE_WITH_HASH
      ]
    )

    array_of_filter_rows = [
      [
        :"in.slug", # DISCUSS: who knows the ID?
        node: my_input_node,
      ],
      [
        :"inject.my_global_id(defaulted)",
        node: Trailblazer::Activity::VariableMapping::Runtime::Filter::Defaulted.build_node(
          id: :"inject.my_global_id(defaulted)",
          default_provider: my_provider_for_default, read_name: :global_id, write_name: :my_global_id,
          args_for_provider: [nil] # FIXME: remove!
        )
      ]
    ]

    input_node = Trailblazer::Activity::VariableMapping::Build::Input.node_for_filters(
      array_of_filter_rows,
      add_default_ctx: true
    )

    lib_ctx, flow_options = assert_run input_node, node: true, seq: [],
      flow_options: {application_ctx: original_ctx = {slug: "0x666", params: {id: 1}, seq: []}}

    shadowed, mutable = flow_options[:application_ctx].decompose
    assert_equal shadowed, original_ctx.merge(my_slug: "0X666", my_global_id: 1)
    assert_equal mutable, {}
  end

  it "Inject(:my_id) => <default> is not called when variable is present" do
    input_node = Trailblazer::Activity::VariableMapping::DSL::Input.node_for_tuples(
      {
        Trailblazer::Activity::VariableMapping::DSL::Inject(:my_id) => ->(ctx, params:, **) { raise }
      },
      add_default_ctx: true
    )

    assert_input input_node,
      {params: {id: 1}, bogus: true, my_id: 2},
      {params: {id: 1}, bogus: true, my_id: 2}
  end

  it "Inject(:my_id) => <default> is called variable is absent" do
    input_node = Trailblazer::Activity::VariableMapping::DSL::Input.node_for_tuples(
      {
        Trailblazer::Activity::VariableMapping::DSL::Inject(:my_id) => ->(ctx, params:, **) { params[:id] + 1 }
      },
      add_default_ctx: true
    )

    assert_input input_node,
      {params: {id: 1}, bogus: true},
      {params: {id: 1}, bogus: true, my_id: 2}
  end

  it "Inject(:my_id, override: true)" do
    input_node = Trailblazer::Activity::VariableMapping::DSL::Input.node_for_tuples(
      {
        Trailblazer::Activity::VariableMapping::DSL::Inject(:my_id, override: true) => ->(ctx, params:, **) { params[:id] }
      },
      add_default_ctx: true
    )

    # Inject is called because {:my_id} is absent in input.
    assert_input input_node,
      {params: {id: 1}, bogus: true,},
      {params: {id: 1}, bogus: true, my_id: 1}

    # override, we still call the Inject logic even though {:my_id} is incoming.
    assert_input input_node,
      {params: {id: 1}, bogus: true, my_id: 2},
      {params: {id: 1}, bogus: true, my_id: 1}
  end

  def assert_input(input_node, original_ctx, expected_shadowed, terminus: nil)
    lib_ctx, flow_options = assert_run input_node, node: true, seq: nil,
      flow_options: {application_ctx: original_ctx},
      terminus: terminus

    shadowed, mutable = flow_options[:application_ctx].decompose
    assert_equal shadowed, expected_shadowed
    assert_equal mutable, {}
  end

  it "DSL converts DSL-tuples to Filters via {Input.node_for_tuples}" do
    my_input_provider       = ->(ctx, slug:, **) { {my_slug: slug.upcase} }
    my_provider_for_default = ->(ctx, params:, **) { params[:id] }

    input_node = Trailblazer::Activity::VariableMapping::DSL::Input.node_for_tuples(
      {
        Trailblazer::Activity::VariableMapping::DSL::In() => [:action, :controller],
        Trailblazer::Activity::VariableMapping::DSL::In() => {:action => :my_action},

        Trailblazer::Activity::VariableMapping::DSL::In() => my_input_provider,
        Trailblazer::Activity::VariableMapping::DSL::Inject(:my_global_id) => my_provider_for_default,
        Trailblazer::Activity::VariableMapping::DSL::Inject() => [:http],

        # inject with override
        # Out with pass_outer_ctx
      },
      add_default_ctx: false # because we got one In()
    )

    assert_input input_node,
      {slug: "0x666", params: {id: 1}, controller: Object, action: :create, bogus: true,},
      {my_slug: "0X666", my_global_id: 1,
        controller: Object, action: :create,
        my_action: :create,
      },
      terminus: Trailblazer::Activity::Left

  # {:http} is present in input
    assert_input input_node,
      {slug: "0x666", params: {id: 1}, seq: [],
        controller: Object, action: :create, bogus: true, http: Module
      },
      {my_slug: "0X666", my_global_id: 1,
        controller: Object, action: :create,
        my_action: :create,
        http: Module,
      }
  end

  it "DSL.node_for_input, default context without any whitelisting" do
    input_node = Trailblazer::Activity::VariableMapping::DSL.node_for_input()

    lib_ctx, flow_options = assert_run input_node, node: true, seq: []

    pp input_node

    assert_equal flow_options[:application_ctx].class, Trailblazer::Activity::VariableMapping::Context
    assert_equal flow_options[:application_ctx].to_h, {seq: []}

    assert_equal flow_options.keys, [:application_ctx]

    my_model_tw = Pipeline(
      my_model_call_task
    )
  end

  it "blacklist everything" do
    # In() => MoreModelInput
    more_model_input = Class.new do
      # Step interface.
      def self.call(ctx, slug:, **)
        {
          slug: slug.downcase
        }
      end
    end



    # tuples = {Trailblazer::Activity::VariableMapping::DSL.In() => []}
    tuples = {Trailblazer::Activity::VariableMapping::DSL.In() => [:params]}

    input_node = Trailblazer::Activity::VariableMapping::DSL.node_for_input(tuples: tuples)
  end
end
