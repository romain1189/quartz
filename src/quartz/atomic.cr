module Quartz
  # This class represent a PDEVS atomic model.
  abstract class AtomicModel < Model
    include Stateful
    include Coupleable
    include Observable
    include Verifiable

    # The precision associated with the model.
    class_property precision_level : Scale = Scale::BASE

    # Defines the precision level associated to this class of models.
    #
    # ### Usage:
    #
    # `precision` must receive a scale unit. The scale unit can be specified
    # with a constant expression (e.g. 'kilo'), with a `Scale` struct or with
    # a number literal.
    #
    # ```
    # precision Scale.::KILO
    # precision -8
    # precision femto
    # ```
    #
    # If specified with a constant expression, the unit argument can be a string
    # literal, a symbol literal or a plain name.
    #
    # ```
    # precision kilo
    # precision "kilo"
    # precision :kilo
    # ```
    #
    # ### Example
    #
    # ```
    # class MyModel < Quartz::AtomicModel
    #   precision femto
    # end
    # ```
    #
    # Is the same as writing:
    #
    # ```
    # class MyModel < Quartz::AtomicModel
    #   self.precision = Scale::FEMTO
    # end
    # ```
    #
    # Or the same as:
    #
    # ```
    # class MyModel < Quartz::AtomicModel; end
    #
    # MyModel.precision = Scale::FEMTO
    # ```
    private macro precision(scale = "base")
      {% if Quartz::ALLOWED_SCALE_UNITS.includes?(scale.id.stringify) %}
        self.precision_level = Quartz::Scale::{{ scale.id.upcase }}
      {% elsif scale.is_a?(NumberLiteral) %}
        self.precision_level = Quartz::Scale.new({{scale}})
      {% else %}
        self.precision_level = {{scale}}
      {% end %}
    end

    # Returns the precision associated with the class.
    def model_precision : Scale
      @@precision_level
    end

    # This attribute is updated automatically along simulation and represents
    # the elapsed time since the last transition.
    property elapsed : Duration = Duration.zero(@@precision_level)

    @bag : Hash(OutputPort, Array(Any)) = Hash(OutputPort, Array(Any)).new { |h, k|
      h[k] = Array(Any).new
    }

    def initialize(name)
      super(name)
      @elapsed = @elapsed.rescale(@@precision_level)
    end

    def initialize(name, state, initial_state = nil)
      super(name)
      @elapsed = @elapsed.rescale(@@precision_level)
      self.initial_state = initial_state if initial_state
      self.state = state
    end

    # The external transition function (δext)
    #
    # Override this method to implement the appropriate behavior of
    # your model.
    #
    # Example:
    # ```
    # def external_transition(messages)
    #   messages.each { |port, value|
    #     puts "#{port} => #{value}"
    #   }
    # end
    # ```
    abstract def external_transition(messages : Hash(InputPort, Array(Any)))

    # Internal transition function (δint), called when the model should be
    # activated, e.g when `#elapsed` reaches `#time_advance`
    #
    # Override this method to implement the appropriate behavior of
    # your model.
    #
    # Example:
    # ```
    # def internal_transition
    #   self.phase = :steady
    # end
    # ```
    abstract def internal_transition

    # This is the default definition of the confluent transition. Here the
    # internal transition is allowed to occur and this is followed by the
    # effect of the external transition on the resulting state.
    #
    # Override this method to obtain a different behavior. For example, the
    # opposite order of effects (external transition before internal
    # transition). Of course you can override without reference to the other
    # transitions.
    def confluent_transition(messages : Hash(InputPort, Array(Any)))
      internal_transition
      external_transition(messages)
    end

    # Time advance function (ta), called after each transition to give a
    # chance to *self* to be active.
    #
    # Override this method to implement the appropriate behavior of
    # your model.
    #
    # Example:
    # ```
    # def time_advance
    #   Quartz.infinity
    # end
    # ```
    abstract def time_advance : Duration

    # The output function (λ)
    #
    # Override this method to implement the appropriate behavior of
    # your model. See `#post` to send values to output ports.
    #
    # Example:
    # ```
    # def output
    #   post(42, :output)
    # end
    abstract def output

    # :nodoc:
    # Used internally by the simulator
    protected def __initialize_state__(processor)
      if @processor != processor
        raise InvalidProcessorError.new("trying to initialize state of model \"#{name}\" from an invalid processor")
      end

      if s = initial_state
        self.state = s
      end
    end

    def inspect(io)
      io << "<" << self.class.name << ": name=" << @name
      io << ", elapsed=" << @elapsed.to_s(io)
      io << ">"
      nil
    end

    # Drops off an output *value* to the specified output *port*.
    #
    # Raises an `InvalidPortHostError` if the given port doesn't belong to this
    # model.
    protected def post(value : Any::Type, on : OutputPort)
      post(Any.new(value), on)
    end

    # Drops off an output *value* to the specified output *port*.
    #
    # Raises an `InvalidPortHostError` if the given port doesn't belong to this
    # model.
    # Raises an `NoSuchPortError` if the given output port doesn't exists.
    @[AlwaysInline]
    protected def post(value : Any::Type, on : Name)
      post(Any.new(value), self.output_port(on))
    end

    protected def post(value : Any, on port : OutputPort)
      raise InvalidPortHostError.new("Given port doesn't belong to this model") if port.host != self
      @bag[port] << value
    end

    protected def post(value : Any, on port : Name)
      post(value, self.output_port(port))
    end

    # :nodoc:
    #
    # Returns outgoing messages added by the DEVS lambda (λ) function for the
    # current state.
    #
    # This method calls the DEVS lambda (λ) function
    # Note: this method should be called only by the simulator.
    def fetch_output! : Hash(OutputPort, Array(Any))
      @bag.clear
      self.output
      @bag
    end
  end
end
