require "../src/quartz"
require "csv"

alias Duration = Quartz::Duration

class Generator < Quartz::AtomicModel
  output :out

  precision micro

  state do
    var n = 0
    var max = 0
    var sigma : Duration do
      Duration.new(RND.rand(1i64..1000i64), Quartz::Scale::MICRO)
    end
  end

  def time_advance : Quartz::Duration
    self.sigma
  end

  def internal_transition
    self.sigma = if n < max
                   Duration.new(RND.rand(1i64..1000i64), model_precision).tap { self.n += 1 }
                 else
                   Duration.infinity(model_precision)
                 end
  end

  def output
    post nil, on: :out
  end

  def external_transition(bag)
  end
end

class Buffer < Quartz::AtomicModel
  input :in, :ready
  output :out

  precision micro

  state do
    var nb_job : Int32 = 0
    var waiting : Bool = false
    var sigma : Duration = Duration::INFINITY
  end

  def external_transition(bag)
    if bag.has_key?(input_port(:in))
      self.nb_job += 1
    end

    if bag.has_key?(input_port(:ready))
      self.waiting = false
    end

    if !waiting && nb_job > 0
      self.sigma = Duration.new(5, model_precision)
    end
  end

  def output
    post nil, on: :out
  end

  def time_advance : Quartz::Duration
    self.sigma
  end

  def internal_transition
    self.sigma = Duration::INFINITY
    self.waiting = true
    self.nb_job -= 1
  end

  def confluent_transition(bag)
    internal_transition
    external_transition(bag)
  end
end

class CPU < Quartz::AtomicModel
  input :task
  output :done

  precision nano

  state do
    var sigma : Duration = Duration::INFINITY
  end

  def external_transition(bag)
    self.sigma = Duration.new(RND.rand(3i64..1000i64**4), model_precision)
  end

  def output
    post nil, on: :done
  end

  def internal_transition
    self.sigma = Duration.infinity(model_precision)
  end

  def time_advance : Quartz::Duration
    self.sigma
  end
end

class GenBufProc < Quartz::CoupledModel
  def initialize(name, max)
    super(name)

    gen = Generator.new(:gen, Generator::State.new(max: max))
    buf = Buffer.new(:buf)
    proc = CPU.new(:proc)

    self << gen
    self << buf
    self << proc

    attach :out, to: :in, between: gen, and: buf
    attach :out, to: :task, between: buf, and: proc
    attach :done, to: :ready, between: proc, and: buf
  end
end

class Tracer
  include Quartz::Hooks::Notifiable
  include Quartz::Observer

  @file : File?

  property filename : String

  def initialize(@filename, notifier)
    notifier.subscribe(Quartz::Hooks::PRE_INIT, self)
    notifier.subscribe(Quartz::Hooks::POST_SIMULATION, self)
    notifier.subscribe(Quartz::Hooks::POST_ABORT, self)
  end

  def close
    @file.try { |f| f.flush; f.close }
  end

  def notify(hook)
    case hook
    when Quartz::Hooks::PRE_INIT
      @file = File.new(@filename, "w+")
      @file.try &.puts "time,n"
    when Quartz::Hooks::POST_SIMULATION, Quartz::Hooks::POST_ABORT
      close
      @file = nil
    else
      # no-op
    end
  end

  def update(model, info)
    return unless model.is_a?(Buffer)
    buf = model.as(Buffer)

    if info
      return if info.not_nil![:transition].as(Quartz::Any).as_sym == :init
    end

    @file.try &.puts "#{info[:time]},#{buf.nb_job}"
  end
end

RND = Random.new(1324)
max = 10000

model = GenBufProc.new(:genbufproc, max)
sim = Quartz::Simulation.new(
  model,
  maintain_hierarchy: false,
  scheduler: :binary_heap
)

model[:buf].add_observer(Tracer.new("genbufproc_trace.csv", sim.notifier))
sim.simulate

puts sim.transition_stats[:TOTAL]
puts sim.elapsed_secs
