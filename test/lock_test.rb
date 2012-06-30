require 'test/unit'
require 'resque'
require 'resque/plugins/lock'

class LockTest < Test::Unit::TestCase
  class Job
    extend Resque::Plugins::Lock
    @queue = :lock_test

    class << self
      attr_accessor :counter
    end

    def self.perform(params={})
      @counter += 1
    end
  end

  def setup
    Job.counter = 0
    Resque.redis.keys('lock:*').each { |key| Resque.redis.del(key) }
    Resque.redis.del('queue:lock_test')
  end

  def test_lint
    assert_nothing_raised do
      Resque::Plugin.lint(Resque::Plugins::Lock)
    end
  end

  def test_version
    major, minor, patch = Resque::Version.split('.')
    assert_equal 1, major.to_i
    assert minor.to_i >= 17
    assert Resque::Plugin.respond_to?(:before_enqueue_hooks)
  end

  def test_lock
    3.times { Resque.enqueue(Job) }

    assert_equal 1, Resque.redis.llen('queue:lock_test')
    assert Resque.redis.exists(Job.lock)
  end

  def test_perform_with_args
    args = [{ 'a' => 1, :b => 2.0, 'c' => '3' }]
    lock_key = Job.lock(*Resque.decode(Resque.encode(args)))
    Resque.enqueue(Job, *args)
    assert Resque.redis.exists(lock_key)
    work_off_jobs
    assert !Resque.redis.exists(lock_key)
    assert_equal 1, Job.counter
  end

  private

  def work_off_jobs
    worker = Resque::Worker.new('*')
    while job = worker.reserve
      worker.perform(job)
    end
  end
end
