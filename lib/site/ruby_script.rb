module Superfluous
  module Site
    module Renderer
      class RubyScript
        def initialize(source)
          @source = source
        end

        def render(context)
          # TODO: Create a scope class per script instead of per script eval?

          # Methods shared by site scripts and templates live in this dynamically generated class,
          # which includes:
          #
          # - the scripts’s `render` method to trigger template rendering, and
          # - any `def`s from the script.
          #
          script_scope_class = Class.new do
            def make_script_binding
              binding
            end
          end
          script_scope = script_scope_class.new

          template_scope = Class.new(script_scope_class) do
            # Note that `render` has a different meaning in templates vs scripts: in a script,
            # it triggers the next step in the rendering pipeline; in a template, it renders a
            # partial and places the result inside this step's content.
            # TODO: Is this bad? Does it defeat generality? Probably.
            #
            define_method(:render, context.render_partial)
          end.new

          # Eval script in our newly created scope
          script_scope_binding = script_scope.make_script_binding
          context.props.each do |k,v|
            script_scope_binding.local_variable_set(k, v)
          end

          # The `render` method available to the script must be dynamically defined so that it can
          # capture `template_scope`
          script_scope_class.define_method(:render) do |**props_from_script, &nested_content|
            yield(
              context
                .with(scope: template_scope)
                .override_props(**props_from_script)
            )
          end

          script_scope_binding.eval(@source.content)
        end
      end
    end
  end
end
