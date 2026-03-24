require "test_helper"

class ComposableTest < Minitest::Spec
  let(:my_create) do
    Class.new do
      def model(ctx, id:, **)
        raise id.inspect
      end
    end
      .new
  end

  it "without any i/o, #model throws exception" do
    my_model_tw = Pipeline(

      [:call_task, :model, Trailblazer::Circuit::Task::Adapter::StepInterface::InstanceMethod]
    )

    exception = assert_raises ArgumentError do
      lib_ctx, flow_options = assert_run my_model_tw, exec_context: my_create, seq: [],
        flow_options: {application_ctx: {controller: Object, params: {id: 1}}}
    end

    assert_equal exception.message, %(missing keyword: :id)
  end
end
