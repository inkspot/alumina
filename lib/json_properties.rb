require 'rubygems'
require 'json'


module Jsonable
	
  def self.included( base )
    # when the module is included in a class, we will
    # use the following to add our class-level methods
    base.extend ClassMethods
  end

  module ClassMethods

    def json_parser(block)
      @json_parser = block
    end
    
    def json_properties( *arr )
      return @jsonable_symbols if arr.empty?
      attr_accessor( *arr )
      @jsonable_symbols ||= []
      @jsonable_symbols.push *arr
      mod = Module.new do
        
        define_method('jsonable_symbols') do
          @jsonable_symbols
        end
        
        define_method('json_parser') do
          @jsonable_symbols
        end
        
        define_method('inherited') do |base|
          base.json_properties *@jsonable_symbols unless !@jsonable_symbols
        end
        
        define_method('from_json') do |json, &block|
          json_hash = case json
          when String: JSON.parse json, {:symbolize_names => true}
          else json
          end
            
          o = self.new
          @jsonable_symbols.each do |symbol|
            val =  case @json_parser 
            when nil: json_hash[symbol]
            else @json_parser.call o, symbol, json_hash[symbol]
            end unless !json_hash[symbol]
            o.instance_variable_set("@#{symbol}", val ) unless !val
          end unless !json_hash
          block.call(o) if block
          o
        end
      end

      extend mod

      define_method('to_json') do |*a|
        json_hash = {}
        self.class.jsonable_symbols.each do |symbol|
          val = instance_variable_get("@#{symbol}")
          json_hash[symbol] = val unless !val or 
                                         (val.respond_to?(:empty?) && val.empty?)
        end
        json_hash.to_json(*a)
      end
    end
  end
end
