require "test_helper"

# Test the normalizer
class DslTest < Minitest::Spec
  it "what" do
    lib_ctx, flow_options, signal = Trailblazer::Activity::VariableMapping::DSL::Normalizer.(
      lib_ctx = {
        user_options: { # DISCUSS: naming is under construction.
          Trailblazer::Activity::VariableMapping::DSL::Inject() => [:http],
          Trailblazer::Activity::VariableMapping::DSL.Out() => ->(ctx, slug:, **) { {my_slug: slug} }
        },
        adds_for_task_wrap: [], # this is part of the DSL specification/convention/whatever.
      },
      {},
      nil,
      **lib_ctx
    )

    assert_equal lib_ctx[:adds_for_task_wrap].size, 2
    assert_equal lib_ctx[:adds_for_task_wrap][0][1..2], [:before, :"task_wrap.call_task"]
    assert_equal lib_ctx[:adds_for_task_wrap][1][1..2], [:after, :"task_wrap.call_task"]
  end

  it "creates empty pipes when no filters wanted" do
    lib_ctx, flow_options, signal = Trailblazer::Activity::VariableMapping::DSL::Normalizer.(
      lib_ctx = {
        user_options: { # DISCUSS: naming is under construction.
        },
        adds_for_task_wrap: [], # this is part of the DSL specification/convention/whatever.
      },
      {},
      nil,
      **lib_ctx
    )

    assert_equal lib_ctx[:adds_for_task_wrap], []
    assert_equal flow_options, {}
    assert_equal signal, nil
  end
end
