module Trailblazer
  class Activity
    module VariableMapping
      # DISCUSS: do we like the location here?
      class Context < Struct.new(:shadowed, :mutable, :original_ctx) # TODO: test me.
        def []=(key, value)
          mutable[key] = value

          # @to_h[key] = value
        end

        def [](key)
          # raise
          mutable[key] || shadowed[key] # FIXME.
        end

        def merge(variables)
          # raise
          # puts variables.inspect
          Context.new(shadowed, mutable.merge(variables))
        end

        def decompose
          return shadowed, mutable
        end

        def to_h
          # return @to_h
          shadowed.to_h.merge(mutable) # DISCUSS: shadowed.to_h we only should do once, at instantiation!
        end

        def to_hash # implicit conversion to Hash.
          to_h
        end
      end
    end
  end
end
