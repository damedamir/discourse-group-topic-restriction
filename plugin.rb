# name: discourse-group-topic-restriction
# about: Restrict topic visibility based on user groups
# version: 1.0
# authors: Your Name
# url: https://github.com/yourname/discourse-group-topic-restriction

enabled_site_setting :group_topic_restriction_enabled

after_initialize do
  module ::DiscourseGroupTopicRestriction
    class Engine < ::Rails::Engine
      engine_name "discourse_group_topic_restriction"
      isolate_namespace DiscourseGroupTopicRestriction
    end
  end

  require_dependency "application_controller"

  class DiscourseGroupTopicRestriction::RestrictController < ::ApplicationController
    requires_plugin "discourse-group-topic-restriction"

    before_action :ensure_admin

    def update_restrictions
      topic = Topic.find(params[:topic_id])
      group_ids = params[:group_ids]
      topic.custom_fields["allowed_groups"] = group_ids
      topic.save!
      render json: success_json
    end

    def fetch_restrictions
      topic = Topic.find(params[:topic_id])
      allowed_groups = topic.custom_fields["allowed_groups"] || []
      render json: { allowed_groups: allowed_groups }
    end
  end

  add_to_serializer(:topic, :allowed_groups) do
    object.custom_fields["allowed_groups"] || []
  end

  TopicQuery.add_custom_filter(:group_restriction) do |result, user|
    if SiteSetting.group_topic_restriction_enabled
      result = result.where("topics.id NOT IN (?)", Topic.where("custom_fields @> ?", { "allowed_groups" => user.group_ids }.to_json))
    end
    result
  end

  Discourse::Application.routes.append do
    post "admin/plugins/group-topic-restriction/update" => "discourse_group_topic_restriction/restrict#update_restrictions"
    get "admin/plugins/group-topic-restriction/fetch" => "discourse_group_topic_restriction/restrict#fetch_restrictions"
  end
end

register_asset "stylesheets/group-topic-restriction.scss"

register_admin_route 'group_topic_restriction.title', 'group-topic-restriction'

Discourse::Application.routes.append do
  get '/admin/plugins/group-topic-restriction' => 'admin/plugins#admin_panel'
end

Admin::PluginsController.class_eval do
  def admin_panel
    render json: {
      groups: Group.all.map { |g| { id: g.id, name: g.name } }
    }
  end
end

register_asset "javascripts/admin/group-topic-restriction.js.es6"

# Ember.js Admin UI
register_html_builder("admin-plugin:group-topic-restriction") do
  <<~HTML
    <div class="group-topic-restriction-container">
      <h2>Group Topic Restriction Settings</h2>
      <label>Select Groups Allowed to View Topics</label>
      <select id="group-selector" multiple>
      </select>
      <button id="save-group-restrictions">Save</button>
    </div>
    <script type="text/javascript">
      document.addEventListener("DOMContentLoaded", function () {
        fetch('/admin/plugins/group-topic-restriction')
          .then(response => response.json())
          .then(data => {
            const select = document.getElementById("group-selector");
            data.groups.forEach(group => {
              let option = document.createElement("option");
              option.value = group.id;
              option.textContent = group.name;
              select.appendChild(option);
            });
          });

        document.getElementById("save-group-restrictions").addEventListener("click", function () {
          const selectedGroups = Array.from(document.getElementById("group-selector").selectedOptions).map(option => option.value);
          fetch('/admin/plugins/group-topic-restriction/update', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ group_ids: selectedGroups })
          }).then(() => alert("Restrictions Updated!"));
        });
      });
    </script>
  HTML
end

