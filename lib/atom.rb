=begin license
   
Copyright (c) 2008, Michael Robinette
All rights reserved.

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, 
this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, 
this list of conditions and the following disclaimer in the documentation 
and/or other materials provided with the distribution.

Neither the name of Michael Robinette nor the names of its contributors may 
be used to endorse or promote products derived from this software without 
specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE 
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR 
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, 
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE 
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=end

require 'net/http'
require 'net/https'
require 'uri'
require 'rexml/document'
require 'rexml/formatters/pretty'
require 'date'
require 'pp'

require 'rubygems'
require 'json'
require './lib/json_properties'


=begin rdoc
   # http://www.atomenabled.org/developers/syndication/atom-format-spec.php
=end


module Atom

   
def Atom.text_node name, value, parent
   if value
      e = REXML::Element.new name
      e << (REXML::Text.new value.to_s)
      parent << e
   end
end

class Error < Exception
   def message
      return "error: #{super}"
   end
end

class Warning < Exception
   def message
      return "warning: #{super}"
   end
end
   
=begin rdoc
   
#  atomFeed =
#     element atom:feed {
#        atomCommonAttributes,
#        (atomAuthor*
#        & atomCategory*
#        & atomContributor*
#        & atomGenerator?
#        & atomIcon?
#        & atomId
#        & atomLink*
#        & atomLogo?
#        & atomRights?
#        & atomSubtitle?
#        & atomTitle
#        & atomUpdated
#        & extensionElement*),
#        atomEntry*
#     }
   
   reading an atom document is not very strict as long as the xml is valid

   writing an atom document is strict

=end
   
class FeedDocument
  include Jsonable
  json_properties :id, 
  	 :updated,
  	 :uri,
	   :title, 
	   :subtitle, 
	   :rights, 
	   :generator, 
	   :logo, 
	   :icon, 
	   :authors, 
	   :contribtors, 
	   :links, 
	   :categories, 
	   :extensions, 
	   :entries
     
  json_parser(Proc.new { |doc, key, value|
    case key
    when :title, :subtitle : 
      Atom::Text.from_json value
    when :authors: 
      value.each {|person| doc << (Atom::Author.from_json person)}
    when :contributors: 
      value.each {|person| doc << (Atom::Contributor.from_json person)}
    when :entries: 
      value.each {|entry| doc << (Atom::Entry.from_json entry)}
    when :generator: 
      Atom::Generator.from_json value
    when :links: 
      value.each {|link|  doc << (Atom::Link.from_json link)}
    when :categories: 
      value.each {|category| doc << (Atom::Category.from_json category)}
    when :extensions: 
      value.each {|extension| doc << (Atom::Extension.from_json category)}
    else value
    end
    })
  
#    attr_accessor :id           # string
#    attr_accessor :title        # Atom::Text
#    attr_accessor :subtitle     # Atom::Text
#    attr_accessor :updated      # string
#    attr_accessor :rights       # string
#    attr_accessor :icon         # uri
#    attr_accessor :logo         # uri
#    attr_accessor :entries      # array of Atom::Entry
#    attr_accessor :authors      # array of Atom::Person
#    attr_accessor :contributors # array of Atom::Person
#    attr_accessor :generator    # Atom::Generator
#    attr_accessor :links        # array of Atom::Link
#    attr_accessor :categories   # array of Atom::Category
#    attr_accessor :extensions   # array of Atom::Extension
    
#    attr_accessor :uri          # URI
    
    AtomNamespace = 'http://www.w3.org/2005/Atom'
    
    def FeedDocument.fetch(o)
      case o
      when URI, String
         feed = FeedDocument.new o
         feed.fetch {|e, msg| yield e, msg if block_given?}
      else
         raise Error.new("need a URI or a string, got a #{o}")
      end
    end
    
    def initialize(url = nil)
       case url
       when URI
          @uri = url
       when String
          @uri = URI.parse(url)
       end
       @authors =        []
       @entries =        []
       @contributors =   []
       @links =          []
       @categories =     []
       @extensions =     []
       yield self if block_given?
     end
    
    def fetch(needs_secure = false )
      http = Net::HTTP.new(@uri.host, needs_secure ? 443 : 80)
 		  http.use_ssl = needs_secure
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if needs_secure

         http_response = http.start do |conn| 
         	conn.get(@uri.request_uri)
         end
         
         parse(http_response.body) {|e, msg| yield e, msg if block_given?}
         self
    end
    
    def parse(o)
       doc = REXML::Document.new(o)
                   
       raise Error.new("XML doc is not an atom document.") unless 
          (doc.root.name == "feed" || doc.root.name == "entry")
       
       parse_feed doc.root do |element, message| 
          yield element, message  unless !block_given?
       end
       
       self
    end
    
    def all_entries_have_authors?
       return true unless 0 == @authors.length
       return !@entries.find { |e| !e.has_author? }
    end
    
    def write(o)
        xml = REXML::Document.new o
        
        yield self if block_given?

        raise Error.new("id is required for atom:feed") unless @id
        raise Error.new("title is required for atom:feed") unless @title
        raise Error.new("updated is required for atom:feed") unless @updated
        raise Error.new("missing author") unless all_entries_have_authors?
        
        xml << (REXML::XMLDecl.new "1.0", "utf-8")
        
        feed = REXML::Element.new "feed" 
        feed.add_namespace AtomNamespace
        Atom.text_node "id", @id, feed
        @title >> feed
        @subtitle >> feed unless !@subtitle
        @rights >> feed unless !@rights
        @generator >> feed unless !@generator
        Atom.text_node "logo", @logo, feed
        Atom.text_node "icon", @icon, feed
         
        @authors.each {|a| a >> feed}
        @contributors.each {|c| c >> feed}
        @links.each {|l| l >> feed}
        @categories.each {|c| c >> feed}
        @extensions.each {|e| e >> feed}
        
        @entries.each {|e| e >> feed}
        
        xml << feed
        fmt = REXML::Formatters::Pretty.new
        fmt.write(xml, o)
        self
    end
    
    
    def parse_feed(feed_element)
       feed_element.each_element do |child|
          
          if (child.namespace != AtomNamespace)
             extensions << parse_extension(child) {|msg| yield child, msg}
             next
          end
          
          case child.name
          when "entry"
             @entries << parse_entry(child) {|msg| yield child, msg}
          when "id"
             @id = URI.parse(child.text)
          when "link"
             @links << parse_link(child) {|msg| yield child, msg}
          when "author"
             @authors << parse_person(child) {|msg| yield child, msg}
          when "contributor"
             @contributors << parse_person(child) {|msg| yield child, msg}
          when "category"
             @categories << parse_category(child) {|msg| yield child, msg}
          when "generator"
             @generator = parse_generator(child) {|msg| yield child, msg}
          when "logo"
             @logo = URI.parse(child)
          when "icon"
             @icon = URI.parse(child)
          when "updated"
             @updated = child.text
          when "rights"
             @rights = parse_text(child) {|msg| yield child, msg}
          when "title"
             @title = parse_text(child) {|msg| yield child, msg}
          when "subtitle"
             @subtitle = parse_text(child) {|msg| yield child, msg}
          else
             yield child, Warning.new("unknown child element of atom:feed")
          end
       end
       
       yield feed_element, 
             Error.new("id required for atom:feed") unless @id
       yield feed_element, 
             Error.new("updated required for atom:feed") unless @updated
       yield feed_element, 
             Error.new("title required for atom:feed") unless @title
       yield feed_element, 
             Error.new("missing author for feed or entry") unless all_entries_have_authors?
           
       self                 
    end
    
    def parse_person(person_element)
       case person_element.name
       when "author":      person = Author.new
       when "contributor": person = Contributor.new
       end
       
       person_element.each_element do |child|
          
         if (child.namespace != AtomNamespace)
            person.extensions << parse_extension(child) { |msg| yield msg } 
            next
         end
         
         case child.name
         when "name"
            person.name = child.text
         when "uri"
            person.uri = URI.parse(child.text)
         when "email"
            person.email = child.text
         else
            yield Warning.new("unknown child element of atom:person")
         end
       end
       
       yield Error.new("name is required for atom:person") unless person.name
       return person.freeze
    end
    
    def parse_link(link_element)
       link = Link.new
       link_element.attributes.each do |name, value|
          case name
          when "href"
             link.href = URI.parse(value)
          when "hreflang"
             link.hreflang = value
          when "rel"
             link.rel = value
          when "length"
             link.length = value
          when "type"
             link.type = value
          when "title"
             link.title = value
          else
             yield Warning.new("unknown attribute in atom:link")
          end
       end
       
       yield Error.new("href is required for atom:link") unless link.href
       return link.freeze
    end
    
    def parse_category(category_element)
       category = Category.new
       category_element.attributes.each do |name, value|
         case name
         when "term"
            category.term = value
         when "scheme"
            category.scheme = URI.parse(value)
         when "label"
            category.label = value
         else
            yield Warning.new("unknown attribute in atom:category")
         end
       end
       yield Error.new("term is required for atom:category") unless category.term
       return category.freeze
    end
    
    def parse_generator(generator_element)
       generator = Generator.new
       generator_element.attributes.each do |name, value|
          case name
          when "uri"
             generator.uri = URI.parse(value)
          when "version"
             generator.version = value
          else
             yield Warning.new("unknown attribute in atom:generator")
          end
       end
       generator.text = generator_element.text
       return generator.freeze
    end
    
    def parse_entry(entry_element)
       entry = Entry.new
       entry_element.each_element do |child|
          
          if (child.namespace != AtomNamespace)
             extensions << parse_extension(child) { |msg| yield msg } 
             next
          end
          
          case child.name
          when "id"
             entry.id = URI.parse(child.text)
          when "link"
             entry.links << parse_link(child) { |msg| yield msg } 
          when "author"
             entry.authors << parse_person(child) { |msg| yield msg } 
          when "contributor"
             entry.contributors << parse_person(child) { |msg| yield msg } 
          when "category"
             entry.categories << parse_category(child) { |msg| yield msg } 
          when "content"
             entry.content = parse_text(child) { |msg| yield msg }
          when "rights"
             entry.rights = parse_text(child) {|msg| yield child, msg}
          when "title"
             entry.title = parse_text(child) {|msg| yield child, msg}
          when "source"
             entry.source = parse_source(child) { |msg| yield msg }
          when "updated"
             entry.updated = child.text
          when "published"
             entry.published = child.text
          when "summary"
             entry.summary = parse_text(child) {|msg| yield child, msg}
          else
             yield Warning.new("unknown child in atom:entry")
          end
       end
       yield Error.new("id required for atom:entry") unless entry.id
       yield Error.new("updated required for atom:entry") unless entry.updated
       yield Error.new("title required for atom:entry") unless entry.title
       return entry.freeze
    end
    
    def parse_source(source_element)
       s = Source.new
       source_element.each_element do |child|
          if (child.namespace != AtomNamespace)
              extensions << parse_extension(child) { |msg| yield msg } 
              next
          end
          
          case child.name
          when "id"
             s.id = URI.parse(child.text)
          when "link"
             s.links << parse_link(child) { |msg| yield msg } 
          when "author"
             s.authors << parse_person(child) { |msg| yield msg } 
          when "contributor"
             s.contributors << parse_person(child) { |msg| yield msg } 
          when "category"
             s.categories << parse_category(child) { |msg| yield msg } 
          when "generator"
             s.generator = parse_generator(child) { |msg| yield msg } 
          when "logo"
             s.logo = URI.parse(child.text)
          when "icon"
             s.icon = URI.parse(child.text)
          when "updated"
             s.updated = child.text
          when "rights"
             s.rights = parse_text(child) {|msg| yield child, msg}
          when "title"
             s.title = parse_text(child) {|msg| yield child, msg}
          when "subtitle"
             s.subtitle = parse_text(child) {|msg| yield child, msg}
          else
             yield Warning.new("unknown child in atom:source")
          end
       end
       return source.freeze
    end
    
    def parse_extension(extension_element)
       extension = Extension.new
       extension_element.attributes.each do |name, value|
          extension.attributes[name] = value
       end
       extension.namespace = extension_element.namespace
       extension.name = extension_element.name
       extension.xml = extension_element.to_s
       return extension.freeze
    end
    
    def parse_text(text_element)
       case text_element.name
       when "content":  text = Content.new
       when "title":    text = Title.new
       when "summary":  text = Summary.new
       when "subtitle": text = Subtitle.new
       when "rights":   text = Rights.new
       else             text = Text.new
       end
       
       type = text_element.attributes['type']
       text.type = type ||'text'
       case type
       when "text"
          text.text = text_element.text
       when "html"
          text.text = text_element.text
       when "xhtml"
          text.text = text_element.elements[1].to_s
       else
          text.type 
          if text_element.attributes['src']
             txt.src = URI.parse(text_element.attributes['src'])
             if text_element.has_elements?
                yield Warning.new("non-empty atom:content with src attribute")
             end
          else
             #type must be a non composite mime type
             text.text = text_element.to_s
          end
       end
       return text.freeze;
    end
    
    def <<(o)
       case o
       when Author:      @authors << o
       when Contributor: @contributors << o
       when Link:        @links << o
       when Entry:       @entries << o
       when Extension:   @extensions << o
       when Category:    @categories << o
       else              raise Error.new("need an Atom::Element, got a: #{o}")
       end
    end
    
end

=begin rdoc

# atomCommonAttributes =
#    attribute xml:base { atomUri }?,
#    attribute xml:lang { atomLanguageTag }?,
#    undefinedAttribute*

=end

class Element
  include Jsonable
  json_properties :base, :lang
end

class Uri < Element

  json_properties :name,
 		 :uri
  
   def initialize uri = nil, name = nil
      @name = name if name
      @uri = uri if uri
   end
   
   def >> xml
      e = REXML::Element.new @name
      e << (REXML::Text.new @uri)
      xml << e
   end		 
end

=begin rdoc

#    atomPersonConstruct =
#        atomCommonAttributes,
#        (element atom:name { text }
#        & element atom:uri { atomUri }?
#        & element atom:email { atomEmailAddress }?
#        & extensionElement*)

=end

class Person < Element

  json_properties :name,
    :uri,
   	:email,
   	:extensions
   
  json_parser(Proc.new { |doc, key, value|
    case key
    when :extensions: 
      value.each {|extension| doc << (Atom::Extension.from_json category)}
    else value
    end
  })
  
   def initialize name = nil
      @name = name if name
      @extensions = []
   end
    
   def >> xml
      raise Error.new("name is required for Atom::Person") unless @name
      
      case self
      when Author:      person = REXML::Element.new "author"
      when Contributor: person = REXML::Element.new "contributor"
      else raise Error.new("person is not an author nor a contributor")
      end

      Atom.text_node "name", @name, person
      Atom.text_node "uri", @uri, person
      Atom.text_node "email", @email, person
       
      @extensions.each {|e| e >> person}
      xml << person
   end
end

class Author      < Person; end 
class Contributor < Person; end

=begin rdoc

# atomEntry =
#    element atom:entry {
#       atomCommonAttributes,
#       (atomAuthor*
#        & atomCategory*
#        & atomContent?
#        & atomContributor*
#        & atomId
#        & atomLink*
#        & atomPublished?
#        & atomRights?
#        & atomSource?
#        & atomSummary?
#        & atomTitle
#        & atomUpdated
#        & extensionElement*)
#    }

=end

class Entry < Element

  json_properties :id,
         :title, 
         :source,
         :updated,
         :published,
         :authors,
         :contributors,
         :content,
         :summary,
         :rights,
         :categories,
         :links,
         :extensions
  
  json_parser(Proc.new { |entry, key, value|
    case key
    when :title, :subtitle, :summary, :rights, :content : 
      Atom::Text.from_json value
    when :authors: 
      value.each {|person| entry << (Atom::Author.from_json person)}
    when :contributors: 
      value.each {|person| entry << (Atom::Contributor.from_json person)}
    when :source: 
      Atom::Source.from_json value
    when :links: 
      value.each {|link|  entry << (Atom::Link.from_json link)}
    when :categories: 
      value.each {|category| entry << (Atom::Category.from_json category)}
    when :extensions: 
      value.each {|extension| entry << (Atom::Extension.from_json category)}
    else value
    end
    })
   
   def initialize title = nil
      @title = (Title.new title) if title
      @authors =       []
      @contributors =  []
      @categories =    []
      @links =         []
      @extensions =    []
      self
   end
   
   def has_author?
      return (@authors.length > 0 || 
             (@source && @source.authors.length > 0))
   end
   
   def <<(o)
      case o
      when Author:      @authors << o
      when Contributor: @contributors << o
      when Link:        @links << o
      when Extension:   @extensions << o
      when Category:    @categories << o
      else              raise Error.new("need an Atom::Element, got a: #{o}")
      end
   end
    
   def >> xml 
      raise Error.new("id is required for atom:entry") unless @id
      raise Error.new("title is required for atom:entry") unless @title
      raise Error.new("updated is required for atom:entry") unless @updated
        
      entry = REXML::Element.new "entry"
      
      Atom.text_node "id", @id, entry
      Atom.text_node "updated", @updated, entry
      @title >> entry
      
      Atom.text_node "published", @published, entry
      @source >> entry unless !@source
      @rights >> entry unless !@rights
        
      @authors.each {|a| a >> entry}
      @contributors.each {|c| c >> entry}
      @links.each {|l| l >> entry}
      @categories.each {|c| c >> entry}
      @extensions.each {|e| e >> entry}
        
      @content >> entry unless !@content
      @summary >> entry unless !@summary
      xml << entry
   end
end

=begin rdoc

# atomCategory =
#   element atom:category {
#      atomCommonAttributes,
#      attribute term { text },
#      attribute scheme { atomUri }?,
#      attribute label { text }?,
#      undefinedContent
#   }

=end
   
class Category < Element
  
  json_properties :term,
    	 :scheme,
    	 :label
   
    def initialize term = nil
      @term = term if term
    end
    
    def >> xml
       raise Error.new("term is required for atom:category") unless @term
       
       cat = REXML::Element.new "category"
       cat.attributes["term"] = @term
       cat.attributes["scheme"] = @scheme unless !@scheme
       cat.attributes["label"] = @label unless !@label
       xml << cat
    end
end

=begin rdoc

# atomSource =
#  element atom:source {
#     atomCommonAttributes,
#     (atomAuthor*
#      & atomCategory*
#      & atomContributor*
#      & atomGenerator?
#      & atomIcon?
#      & atomId?
#      & atomLink*
#      & atomLogo?
#      & atomRights?
#      & atomSubtitle?
#      & atomTitle?
#      & atomUpdated?
#      & extensionElement*)
#    }

=end

class Source < Element

  json_parser(Proc.new { |source, key, value|
    case key
    when :title, :subtitle, :summary, :rights, :content : 
      Atom::Text.from_json value
    when :authors: 
      value.each {|person| source << (Atom::Author.from_json person)}
    when :contributors: 
      value.each {|person| source << (Atom::Contributor.from_json person)}
    when :generator: 
      Atom::Generator.from_json value
    when :links: 
      value.each {|link| source << (Atom::Link.from_json link)}
    when :categories: 
      value.each {|category| source << (Atom::Category.from_json category)}
    when :extensions: 
      value.each {|extension| source << (Atom::Extension.from_json category)}
    else value
    end
  })
  
    
   def initialize
      @authors =       []
      @contributors =  []
      @categories =    []
      @links =         []
      @extensions =    []
   end
    
   def <<(o)
      case o
      when Author:      @authors << o
      when Contributor: @contributors << o
      when Link:        @links << o
      when Extension:   @extensions << o
      when Category:    @categories << o
      else              raise Error.new("an Atom::Element type, got a: #{o}")
      end
   end
    
   def >> xml
      source = REXML::Element.new "source"
       
      Atom.text_node "id", @id, source
      @title >> source unless !@title
      @subtitle >> source unless !@subtitle
      @rights >> source unless !@rights
      @generator >> source unless !@generator
      
      Atom.text_node "updated", @updated, source
      Atom.text_node "logo", @logo, source
      Atom.text_node "icon", @icon, source
                 
      @authors.each {|a| e >> source}
      @contributors.each {|c| c >> source}
      @links.each {|l| l >> source}
      @categories.each {|c| c >> source}
      @extensions.each {|e| e >> source}

      xml << source
   end
   
   json_properties :id,
      	 :title,
      	 :subtitile,
      	 :rights,
      	 :generator,
      	 :source,
      	 :logo,
      	 :icon,
      	 :authors,
      	 :contributors,
      	 :links,
      	 :categories,
      	 :extensions
end

=begin rdoc
# atomLink =
#   element atom:link {
#     atomCommonAttributes,
#     attribute href { atomUri },
#     attribute rel { atomNCName | atomUri }?,
#     attribute type { atomMediaType }?,
#     attribute hreflang { atomLanguageTag }?,
#     attribute title { text }?,
#     attribute length { text }?,
#     undefinedContent
#  }
=end
 
class Link < Element
    
    def initialize href = nil
      @href = href if href
      self
    end
    
    def >> xml
       raise Error.new("href is required for atom:link") unless @href

       link = REXML::Element.new "link"
       link.attributes["href"] = @href
       link.attributes["rel"] = @rel unless !@rel
       link.attributes["type"] = @type unless !@type
       link.attributes["hreflang"] = @hreflang unless !@hreflang
       link.attributes["title"] = @title unless !@title
       link.attributes["length"] = @length unless !@length
       
       xml << link
    end
    
    json_properties :href,
      	 :rel,
      	 :type,
      	 :hreflang,
      	 :title,
      	 :length

end

=begin rdoc
atomPlainTextConstruct =
   atomCommonAttributes,
   attribute type { "text" | "html" }?,
   text

atomXHTMLTextConstruct =
   atomCommonAttributes,
   attribute type { "xhtml" },
   xhtmlDiv

atomTextConstruct = atomPlainTextConstruct | atomXHTMLTextConstruct
=end

class Text < Element

   def initialize text = nil
      @text = text if text
   end
    
   def >> xml
      case self
      when Content:  e = REXML::Element.new "content"
      when Summary:  e = REXML::Element.new "summary"
      when Title:    e = REXML::Element.new "title"
      when Rights:   e = REXML::Element.new "rights"
      when Subtitle: e = REXML::Element.new "subtitle"
      end
       
      if !e
         xml.text = @text
         xml.attributes["type"] = @type unless !@type
      else
         e.text = @text
         e.attributes["type"] = @type unless !@type
         xml << e
      end
       
      xml
   end
   
   json_properties :type,
      	 :text

end

class Content  < Text; end
class Summary  < Text; end
class Title    < Text; end
class Subtitle < Text; end
class Rights   < Text; end

=begin rdoc
# atomGenerator = 
#   element atom:generator {
#     atomCommonAttributes,
#     attribute uri { atomUri }?,
#     attribute version { text }?,
#     text
#  }
=end

class Generator < Element
  
   def initialize text = nil
      @text = text if text
   end
   
   def >> xml
      gen = REXML::Element.new "generator"
      gen.text = @text
      gen.attributes["uri"] = @uri unless !@uri
      gen.attributes["version"] = @version unless !@version   

      xml << gen
   end
   
   json_properties :text,
      	 :uri,
      	 :version

end

class Extension
  include Jsonable
   
   def initialize
      @attributes = {}
   end
   
   def >> xml
      ext = REXML::Element.new @name
      ext.text = @xml
      attributes.each {|name, value| ext.attributes[name] = value}

      xml << ext
   end
   
   json_properties :attributes,
      	 :namespace,
      	 :name,
      	 :xml

end
end




