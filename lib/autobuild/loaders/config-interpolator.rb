require 'autobuild/exceptions'

module Autobuild
    class UndefinedVariable < ConfigException
        attr_reader :name
        attr_accessor :reference
        def initialize(name, reference = [])
            @name = name 
            @reference = reference
        end

        def to_s
            "undefined variable '#{name}' in #{reference.join('/')}"
        end
    end

    class Interpolator
        VarDefKey = 'defines'
        MatchExpr = '\$\{([^}]+)\}|\$(\w+)'
        PartialMatch = Regexp.new(MatchExpr)
        WholeMatch = Regexp.new("^(?:#{MatchExpr})$")

        def self.interpolate(config, parent = nil)
            Interpolator.new(config, parent).interpolate
        end

        def initialize(node, parent = nil, variables = {})
            @node = node
            @variables = {}
            @defines = {}
            @parent = parent
        end

        def interpolate
            case @node
            when Hash
                @defines = (@node[VarDefKey] || {})

                interpolated = Hash.new
                @node.each do |k, v|
                    begin
                        next if k == VarDefKey
                        interpolated[k] = Interpolator.interpolate(v, self)
                    rescue UndefinedVariable => e
                        e.reference.unshift k
                        raise e
                    end
                end

                interpolated

            when Array
                @node.collect { |v| Interpolator.interpolate(v, self) }

            else
                begin
                    each_interpolation(@node) { |varname| value_of(varname) }
                rescue UndefinedVariable => e
                    e.reference.unshift @node.to_str if @node.respond_to?(:to_str)
                    raise e
                end
            end
        end

        def value_of(name)
            if @defines.has_key?(name)
                value = @defines.delete(name)
                @variables[name] = each_interpolation(value) { |varname|
                    begin
                        value_of(varname)
                    rescue UndefinedVariable => e
                        if e.varname == name
                            raise ConfigException, "cyclic reference found in definition of '#{name}'"
                        else
                            raise
                        end
                    end
                }
            elsif @variables.has_key?(name)
                @variables[name]
            elsif @parent
                @parent.value_of(name)
            elsif ENV[name.to_s]
                ENV[name.to_s]
            else
                raise UndefinedVariable.new(name)
            end
        end

        def each_interpolation(value)
            return value if (!value.respond_to?(:to_str) || value.empty?)
            
            # Special case: if 'value' is *only* an interpolation, avoid
            # conversion to string
            if match = WholeMatch.match(value)
                return yield($1 || $2)
            end

            return value.gsub(PartialMatch) { |match|
                varname = $1 || $2
                yield(varname)
            }
        end
    end
end

