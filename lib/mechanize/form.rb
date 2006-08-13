module WWW
  class Mechanize
    # =Synopsis
    # GlobalForm provides all access to form fields, such as the buttons,
    # check boxes, and text input.
    #
    # GlobalForm takes two nodes, the node where the form tag is located
    # (form_node), and another node, from which to start looking for form
    # elements (elements_node) like buttons and the like. For class Form
    # both fall together into one and the same node.
    #
    # Class Form does not work in the case there is some invalid (unbalanced)
    # html involved, such as: 
    #
    #   <td>
    #     <form>
    #   </td>
    #   <td>
    #     <input .../>
    #     </form>
    #   </td>
    # 
    class GlobalForm
      attr_reader :form_node, :elements_node
      attr_accessor :method, :action, :name
    
      attr_reader :fields, :buttons, :file_uploads, :radiobuttons, :checkboxes
      attr_reader :enctype
    
      def initialize(form_node, elements_node)
        @form_node, @elements_node = form_node, elements_node
    
        @form_node.attributes ||= {}
        @method = (@form_node.attributes['method'] || 'GET').upcase
        @action = @form_node.attributes['action'] 
        @name = @form_node.attributes['name']
        @enctype = @form_node.attributes['enctype'] || 'application/x-www-form-urlencoded'
        @clicked_buttons = []
    
        parse
      end
    
      # This method builds an array of arrays that represent the query
      # parameters to be used with this form.  The return value can then
      # be used to create a query string for this form.
      def build_query(buttons = [])
        query = []
    
        fields().each do |f|
          next unless f.value
          query.push(*f.query_value)
        end
    
        checkboxes().each do |f|
          query.push(*f.query_value) if f.checked
        end
    
        radio_groups = {}
        radiobuttons().each do |f|
          radio_groups[f.name] ||= []
          radio_groups[f.name] << f 
        end
    
        # take one radio button from each group
        radio_groups.each_value do |g|
          checked = g.select {|f| f.checked}
    
          if checked.size == 1
            f = checked.first
            query.push(*f.query_value)
          elsif checked.size > 1 
            raise "multiple radiobuttons are checked in the same group!" 
          end
        end

        @clicked_buttons.each { |b|
          query.push(*b.query_value)
        }
    
        query
      end

      # This method adds a button to the query.  If the form needs to be
      # submitted with multiple buttons, pass each button to this method.
      def add_button_to_query(button)
        @clicked_buttons << button
      end
    
      # This method calculates the request data to be sent back to the server
      # for this form, depending on if this is a regular post, get, or a
      # multi-part post,
      def request_data
        query_params = build_query()
        query = nil
        case @enctype.downcase
        when 'multipart/form-data'
          boundary = rand_string(20)
          @enctype << "; boundary=#{boundary}"
          params = []
          query_params.each { |k,v| params << param_to_multipart(k, v) }
          @file_uploads.each { |f| params << file_to_multipart(f) }
          query = params.collect { |p| "--#{boundary}\r\n#{p}" }.join('') +
            "--#{boundary}--\r\n"
        else
          query = WWW::Mechanize.build_query_string(query_params)
        end

        query
      end
    
      private
      def parse
        @fields       = WWW::Mechanize::List.new
        @buttons      = WWW::Mechanize::List.new
        @file_uploads = WWW::Mechanize::List.new
        @radiobuttons = WWW::Mechanize::List.new
        @checkboxes   = WWW::Mechanize::List.new
    
        # Find all input tags
        (@elements_node/'input').each do |node|
          node.attributes ||= {}
          type = (node.attributes['type'] || 'text').downcase
          name = node.attributes['name']
          next if type != 'submit' && name.nil?
          case type
          when 'text', 'password', 'hidden', 'int'
            @fields << Field.new(node.attributes['name'], node.attributes['value'] || '') 
          when 'radio'
            @radiobuttons << RadioButton.new(node.attributes['name'], node.attributes['value'], node.attributes.has_key?('checked'), self)
          when 'checkbox'
            @checkboxes << CheckBox.new(node.attributes['name'], node.attributes['value'], node.attributes.has_key?('checked'), self)
          when 'file'
            @file_uploads << FileUpload.new(node.attributes['name'], node.attributes['value']) 
          when 'submit'
            @buttons << Button.new(node.attributes['name'], node.attributes['value'])
          when 'image'
            @buttons << ImageButton.new(node.attributes['name'], node.attributes['value'])
          end
        end

        # Find all textarea tags
        (@elements_node/'textarea').each do |node|
          next if node.attributes.nil?
          next if node.attributes['name'].nil?
          @fields << Field.new(node.attributes['name'], node.all_text)
        end

        # Find all select tags
        (@elements_node/'select').each do |node|
          next if node.attributes.nil?
          next if node.attributes['name'].nil?
          if node.attributes.has_key? 'multiple'
            @fields << MultiSelectList.new(node.attributes['name'], node)
          else
            @fields << SelectList.new(node.attributes['name'], node)
          end
        end
      end

      def rand_string(len = 10)
        chars = ("a".."z").to_a + ("A".."Z").to_a
        string = ""
        1.upto(len) { |i| string << chars[rand(chars.size-1)] }
        string
      end
    
      def mime_value_quote(str)
        str.gsub(/(["\r\\])/){|s| '\\' + s}
      end

      def param_to_multipart(name, value)
        return "Content-Disposition: form-data; name=\"" +
                "#{mime_value_quote(name)}\"\r\n" +
                "\r\n#{value}\r\n"
      end
    
      def file_to_multipart(file)
        body =  "Content-Disposition: form-data; name=\"" +
                "#{mime_value_quote(file.name)}\"; " +
                "filename=\"#{mime_value_quote(file.file_name || '')}\"\r\n" +
                "Content-Transfer-Encoding: binary\r\n"
        if file.mime_type != nil
          body << "Content-Type: #{file.mime_type}\r\n"
        end
    
        body << "\r\n#{file.file_data}\r\n"
    
        body
      end
    end
    
    # =Synopsis
    # This class encapsulates a form parsed out of an HTML page.  Each type
    # of input fields available in a form can be accessed through this object.
    # See GlobalForm for more methods.
    #
    # ==Example
    # Find a form and print out its fields
    #  form = page.forms.first # => WWW::Mechanize::Form
    #  form.fields.each { |f| puts f.name }
    class Form < GlobalForm
      attr_reader :node
    
      def initialize(node)
        @node = node
        super(@node, @node)
      end

      # Fetch the first field whose name is equal to field_name
      def field(field_name)
        fields.find { |f| f.name.eql? field_name }
      end

      # This method sets multiple fields on the form.  It takes a list of field
      # name, value pairs.  If there is more than one field found with the
      # same name, this method will set the first one found.  If you want to
      # set the value of a duplicate field, use a value which is an Array with
      # the second value of the array as the index in to the form.  The index
      # is zero based.  For example, to set the second field named 'foo', you
      # could do the following:
      #  form.set_fields( :foo => ['bar', 1] )
      def set_fields(fields = {})
        fields.each do |k,v|
          value = nil
          index = 0
          v.each do |val|
            index = val.to_i unless value.nil?
            value = val if value.nil?
          end
          self.fields.name(k.to_s).[](index).value = value
        end
      end

      # Treat form fields like accessors.
      def method_missing(id,*args)
        method = id.to_s.gsub(/=$/, '')
        if field(method)
          return field(method).value if args.empty?
          return field(method).value = args[0]
        end
        super
      end
    end
  end
end
