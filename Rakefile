require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create do |t|
  t.test_globs = ["test/filter_test.rb", "test/task_wrap_pipes_test.rb", "test/dsl_test.rb"]
end

task default: :test

Minitest::TestTask.create :dsl do |t|
  t.test_globs = ["test/integration/activity_test.rb"]
end
