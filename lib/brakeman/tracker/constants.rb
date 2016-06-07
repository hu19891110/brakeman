require 'brakeman/processors/output_processor'

module Brakeman
  class Constant
    attr_reader :name, :file

    def initialize name, value = nil, context = nil 
      set_name name, context
      @values = [ value ]
      @context = context

      if @context
        @file = @context[:file]
      end
    end

    def line
      if @values.first.is_a? Sexp
        @values.first.line
      end
    end

    def set_name name, context
      @name = Constants.constant_as_array(name)
    end

    def match? name
      @name.reverse.zip(name.reverse).reduce(true) { |m, a| a[1] ? a[0] == a[1] && m : m }
    end

    def value
      @values.reverse.reduce do |m, v|
        Sexp.new(:or, v, m)
      end
    end

    def add_value exp
      unless @values.include? exp
        @values << exp
      end
    end
  end

  class Constants
    include Brakeman::Util

    def initialize
      @constants = Hash.new { |h, k| h[k] = [] }
    end

    def size
      @constants.length
    end

    def [] exp
      return unless constant? exp
      match = find_constant exp

      if match
        match.value
      else
        nil
      end
    end

    def find_constant exp
      base_name = Constants.get_constant_base_name(exp)
 #     puts "Looking up #{exp.inspect} - #{base_name.inspect}"

      if @constants.key? base_name
        name = Constants.constant_as_array(exp)

        @constants[base_name].find do |c|
          c.match? name
        end
      end
    end

    def add name, value, context = nil
      value = truncate_value(value)

      if false#existing = self.find_constant(name)
        abort("OMG A REASSIGNMENT")
        existing.add_value value
      else
        base_name = Constants.get_constant_base_name(name)
        @constants[base_name] << Constant.new(name, value, context)
      end
    end

    def get_literal name
      if x = self[name] and [:lit, :false, :str, :true, :array, :hash].include? x.node_type
        x
      else
        nil
      end
    end

    def each
      @constants.each do |name, values|
        values.each do |constant|
          yield constant
        end
      end
    end

    def truncate_value value
      # Treat [1,2,3].freeze as [1,2,3]
      if call? value and value.method == :freeze
        value = value.target
      end

      # If the value is large, truncate it
      if node_type? value, :array, :hash and value.length > 11
        value = value.take(10)

        if hash? value
          value << s(:lit, :rest) << s(:lit, :'...')
        else
          value << s(:lit, :'...')
        end
      end

      value
    end

    def self.constant_as_array exp
      get_constant_name(exp).split('::')
    end

    def self.get_constant_name exp
      if exp.is_a? Sexp
        Brakeman::OutputProcessor.new.format(exp)
      else
        exp.to_s
      end
    end

    def self.get_constant_base_name exp
      return exp unless exp.is_a? Sexp

      case exp.node_type
      when :const, :colon3
        exp.value
      when :colon2
        exp.last
      else
        exp
      end
    end
  end
end
