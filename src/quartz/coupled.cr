module Quartz
  # This class represent a PDEVS coupled model.
  class CoupledModel < Model
    include Coupleable
    include Coupler
    include Observable

    class_property! preferred_event_set : Symbol

    # Defines the preferred event set for this particular class of coupled
    # models. Specified event set will be used to coordinate childrens in all
    # instances of this coupled model.
    #
    # Writing:
    #
    # ```
    # class MyCoupled < CoupledModel
    #   event_set ladder_queue
    # end
    # ```
    #
    # Is the same as writing:
    #
    # ```
    # class MyCoupled < CoupledModel
    #   self.preferred_event_set = :ladder_queue
    # end
    # ```
    #
    # Or the same as:
    #
    # ```
    # class MyCoupled < CoupledModel; end
    #
    # MyCoupled.preferred_event_set = :ladder_queue
    # ```
    #
    # The argument can be a string literal, a symbol literal or a plain name.
    macro event_set(name)
      self.preferred_event_set = :{{ name.id }}
    end
  end
end
