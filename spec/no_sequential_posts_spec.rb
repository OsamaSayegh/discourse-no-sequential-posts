require "rails_helper"

describe "No sequential posts plugin" do
  let(:user) { Fabricate(:user) }
  let(:admin) { Fabricate(:admin) }
  let(:topic) { Fabricate(:topic, first_post: Fabricate(:post)) }
  let(:private_message) { Fabricate(:private_message_topic, first_post: Fabricate(:post)) }

  def create_post(user, t = nil)
    # calling this method is the same as fabricating a post ONLY if it succeeds
    # i.e. if `.success?` is true then a post will be created on the topic whose
    # id is passed as `topic_id` to params

    t ||= topic
    params = {
      raw: "Hello there! This is a test post!",
      archetype: "regular",
      category: "",
      topic_id: t.id,
      typing_duration_msecs: "2700",
      composer_open_duration_msecs: "12556",
      ip_address: "127.0.0.1",
      user_agent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.87 Safari/537.36",
      referrer: "http://localhost:3000/",
    }
    NewPostManager.new(user, params).perform
  end

  before do
    SiteSetting.no_sequential_posts_plugin_enabled = true
  end

  it "doesn't let anyone create a post in a topic if the last post in that topic belongs to them" do
    Fabricate(:post, topic_id: topic.id, user: admin)
    expect(create_post(admin).success?).to be_falsey
    expect(create_post(user).success?).to be_truthy
    expect(create_post(admin).success?).to be_truthy

    Fabricate(:post, topic_id: topic.id, user: user)
    expect(create_post(user).success?).to be_falsey
  end

  context "when `no_sequential_posts_until_x_seconds_passed` site setting is set to 0" do
    before do
      SiteSetting.no_sequential_posts_until_x_seconds_passed = 0
    end

    it "allows the user to post again only when another user repliess" do
      old_topic = Fabricate(:topic, first_post: Fabricate(:post, created_at: 3.years.ago))
      Fabricate(:post, topic_id: old_topic.id, user: admin, created_at: 2.years.ago)

      expect(create_post(admin, old_topic).success?).to be_falsey
      expect(create_post(user, old_topic).success?).to be_truthy

      expect(create_post(user, old_topic).success?).to be_falsey
      expect(create_post(admin, old_topic).success?).to be_truthy
    end
  end

  it "makes an exception if the last post by the user is old enough" do
    SiteSetting.no_sequential_posts_until_x_seconds_passed = 600

    post1 = Fabricate(:post, topic_id: topic.id, user: admin)
    expect(create_post(admin).success?).to be_falsey

    post1.created_at = 601.seconds.ago
    post1.save!
    expect(create_post(admin).success?).to be_truthy
  end

  it "always allows the user to post if they're in an exempted group" do
    Fabricate(:post, topic_id: topic.id, user: user)

    group = Fabricate(:group, name: "exempted")
    group.add(user)
    group.save!
    expect(create_post(user).success?).to be_falsey

    SiteSetting.no_sequential_posts_exempted_groups = "exempted"
    expect(create_post(user).success?).to be_truthy
  end

  it "allows non-human users to create as many posts as they want" do
    expect(create_post(Discourse.system_user).success?).to be_truthy
    expect(create_post(Discourse.system_user).success?).to be_truthy
    expect(create_post(Discourse.system_user).success?).to be_truthy
  end

  it "doesn't apply to private message" do
    private_message.topic_allowed_users.create!(user_id: user.id)
    expect(create_post(user, private_message).success?).to be_truthy
    expect(create_post(user, private_message).success?).to be_truthy
    expect(create_post(user, private_message).success?).to be_truthy
  end
end
