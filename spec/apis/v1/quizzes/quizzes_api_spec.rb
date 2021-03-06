
# Copyright (C) 2012 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require File.expand_path(File.dirname(__FILE__) + '/../../api_spec_helper')
require File.expand_path(File.dirname(__FILE__) + '/../../locked_spec')

describe Quizzes::QuizzesApiController, type: :request do

  context 'locked api item' do
    let(:item_type) { 'quiz' }

    let(:locked_item) do
      quiz = @course.quizzes.create!(:title => 'Locked Quiz')
      quiz.publish!
      quiz
    end

    def api_get_json
      api_call(
        :get,
        "/api/v1/courses/#{@course.id}/quizzes/#{locked_item.id}",
        {:controller=>'quizzes/quizzes_api', :action=>'show', :format=>'json', :course_id=>"#{@course.id}", :id => "#{locked_item.id}"},
      )
    end

    include_examples 'a locked api item'
  end

  describe "GET /courses/:course_id/quizzes (index)" do
    before(:once) { teacher_in_course(:active_all => true) }

    it "should return list of quizzes" do
      quizzes = (0..3).map{ |i| @course.quizzes.create! :title => "quiz_#{i}" }

      json = api_call(:get, "/api/v1/courses/#{@course.id}/quizzes",
                      :controller=>"quizzes/quizzes_api", :action=>"index", :format=>"json", :course_id=>"#{@course.id}")

      quiz_ids = json.collect { |quiz| quiz['id'] }
      expect(quiz_ids).to eq quizzes.map(&:id)
    end

    it "should search for quizzes by title" do
      2.times{ |i| @course.quizzes.create! :title => "first_#{i}" }
      ids = @course.quizzes.map(&:id)
      2.times{ |i| @course.quizzes.create! :title => "second_#{i}" }

      json = api_call(:get, "/api/v1/courses/#{@course.id}/quizzes?search_term=fir",
                      :controller=>"quizzes/quizzes_api", :action=>"index", :format=>"json", :course_id=>"#{@course.id}",
                      :search_term => 'fir')

      expect(json.map{|h| h['id'] }.sort).to eq ids.sort
    end

    it "should return unauthorized if the quiz tab is disabled" do
      @course.tab_configuration = [ { :id => Course::TAB_QUIZZES, :hidden => true } ]
      @course.save!
      student_in_course(:active_all => true, :course => @course)
      raw_api_call(:get, "/api/v1/courses/#{@course.id}/quizzes",
                   :controller => "quizzes/quizzes_api",
                   :action => "index",
                   :format => "json",
                   :course_id => "#{@course.id}")
      assert_status(404)
    end
    it "limits student requests to published quizzes" do
      student_in_course(:active_all => true)
      quizzes = (0..1).map { |i| @course.quizzes.create! :title => "quiz_#{i}"}
      published_quiz = quizzes.first
      published_quiz.publish!
      json = api_call(:get, "/api/v1/courses/#{@course.id}/quizzes",
                      :controller => 'quizzes/quizzes_api',
                      :action => 'index',
                      :format => 'json',
                      :course_id => "#{@course.id}")
      quiz_ids = json.collect { |quiz| quiz['id'] }
      expect(quiz_ids).to eq [ published_quiz.id]
    end

    context "jsonapi style" do

      it "renders a jsonapi style response" do
        quizzes = (0..3).map{ |i| @course.quizzes.create! :title => "quiz_#{i}" }

        json = api_call(:get, "/api/v1/courses/#{@course.id}/quizzes",
                        {:controller=>"quizzes/quizzes_api", :action=>"index", :format=>"json", :course_id=>"#{@course.id}"},
                        {},
                        'Accept' => 'application/vnd.api+json')
        meta = json['meta']
        meta = json['meta']
        expect(meta['permissions']['quizzes']['create']).to eq true

        json = json['quizzes']
        quiz_ids = json.collect { |quiz| quiz['id'] }
        expect(quiz_ids).to eq quizzes.map(&:id).map(&:to_s)

      end

      it "limits student requests to available quizzes" do
        student_in_course(:active_all => true)
        quizzes = (0..3).map{ |i| @course.quizzes.create! :title => "quiz_#{i}" }
        available_quiz = quizzes.first
        available_quiz.workflow_state = 'available'
        available_quiz.save!

        json = api_call(:get, "/api/v1/courses/#{@course.id}/quizzes",
                        {:controller=>"quizzes/quizzes_api", :action=>"index", :format=>"json", :course_id=>"#{@course.id}"},
                        {},
                        'Accept' => 'application/vnd.api+json')
        json = json['quizzes']
        quiz_ids = json.collect { |quiz| quiz['id'] }
        expect(quiz_ids).to eq [ available_quiz.id.to_s ]
      end
    end
  end

  describe "GET /courses/:course_id/quizzes/:id (show)" do
    before(:once) { course_with_teacher(:active_all => true, :course => @course) }

    context "unpublished quiz" do
      before do
        @quiz = @course.quizzes.create! :title => 'title'
        @quiz.quiz_questions.create!(:question_data => { :name => "test 1" })
        @quiz.save!

        @json = api_call(:get, "/api/v1/courses/#{@course.id}/quizzes/#{@quiz.id}",
                        :controller=>"quizzes/quizzes_api", :action=>"show", :format=>"json", :course_id=>"#{@course.id}", :id => "#{@quiz.id}")
      end

      it "includes unpublished questions in question count" do
        expect(@json['question_count']).to eq 1
      end
    end

    context "jsonapi style request" do

      it "renders in a jsonapi style" do
        @quiz = @course.quizzes.create! title: 'Test Quiz'
        @json = api_call(:get, "/api/v1/courses/#{@course.id}/quizzes/#{@quiz.id}",
                         { :controller=>"quizzes/quizzes_api", :action=>"show", :format=>"json", :course_id=>"#{@course.id}", :id => "#{@quiz.id}"}, {},
                        'Accept' => 'application/vnd.api+json')
        @json = @json.fetch('quizzes').map { |q| q.with_indifferent_access }
        expect(@json).to match_array [
          Quizzes::QuizSerializer.new(@quiz, scope: @user, controller: controller, session: session).
          as_json[:quiz].with_indifferent_access
        ]
      end
    end

    context "non-existent quiz" do
      before do
        @json = api_call(:get, "/api/v1/courses/#{@course.id}/quizzes/10101",
                        {:controller=>"quizzes/quizzes_api", :action=>"show", :format=>"json", :course_id=>"#{@course.id}", :id => "10101"},
                        {}, {}, {:expected_status => 404})
      end

      it "should return a not found error message" do
        expect(@json.inspect).to include "does not exist"
      end
    end
  end

  describe "POST /courses/:course_id/quizzes (create)" do
    def api_create_quiz(quiz_params, opts={})
      api_call(:post, "/api/v1/courses/#{@course.id}/quizzes",
              {:controller=>"quizzes/quizzes_api", :action => "create", :format=>"json", :course_id=>"#{@course.id}"},
              {:quiz => quiz_params}, {}, opts)
    end

    before(:once) { teacher_in_course(:active_all => true) }

    let (:new_quiz) { @course.quizzes.first }

    context "jsonapi style request" do

      it "renders in a jsonapi style" do
        @json = api_call(:post, "/api/v1/courses/#{@course.id}/quizzes",
                         { :controller=>"quizzes/quizzes_api", :action=>"create", :format=>"json", :course_id=>"#{@course.id}" },
                         { quizzes: [{ 'title' => 'blah blah', 'published' => true }] },
                        'Accept' => 'application/vnd.api+json')
        @json = @json.fetch('quizzes').map { |q| q.with_indifferent_access }
        @course.reload
        @quiz = @course.quizzes.first
        expect(@json).to match_array [
          Quizzes::QuizSerializer.new(@quiz, scope: @user, controller: controller, session: session).
          as_json[:quiz].with_indifferent_access
        ]
      end
    end

    it "creates a quiz for the course" do
      api_create_quiz({ 'title' => 'testing' })
      expect(new_quiz.title).to eq 'testing'
    end

    it "doesn't allow setting fields not in the whitelist" do
      api_create_quiz({ 'assignment_id' => 123 })
      expect(new_quiz.assignment_id).to be_nil
    end

    it "allows creating a published quiz" do
      api_create_quiz('published' => true)
      expect(new_quiz).to be_published
    end

    it "renders an error when the title is too long" do
      title = 'a' * ActiveRecord::Base.maximum_string_length + '!'
      json = api_create_quiz({ 'title' => title }, :expected_status => 400 )
      expect(json).to have_key 'errors'
      expect(new_quiz).to be_nil
    end

    describe "validations" do
      context "assignment_group_id" do
        let_once(:my_group) { @course.assignment_groups.create! :name => 'my group' }
        let_once(:other_course) { Course.create! :name => 'other course' }
        let_once(:other_group) { other_course.groups.create! :name => 'other group' }

        it "should put the quiz in a group owned by its course" do
          api_create_quiz({'title' => 'test quiz', 'assignment_group_id' => my_group.id})
          expect(new_quiz.assignment_group_id).to eq my_group.id
        end

        it "should not put the quiz in a group not owned by its course" do
          api_create_quiz({'title' => 'test quiz', 'assignment_group_id' => other_group.id})
          expect(new_quiz.assignment_group_id).not_to eq other_group.id
        end
      end

      context "hide_results" do
        it "should set hide_results='until_after_last_attempt' if allowed_attempts > 1" do
          api_create_quiz({'hide_results' => 'until_after_last_attempt', 'allowed_attempts' => 3})
          expect(new_quiz.hide_results).to eq 'until_after_last_attempt'
        end

        it "should not hide_results='until_after_last_attempt' if allowed_attempts == 1" do
          api_create_quiz({'hide_results' => 'until_after_last_attempt', 'allowed_attempts' => 1})
          expect(new_quiz.hide_results).not_to eq 'until_after_last_attempt'
        end

        it "should not hide_results='until_after_last_attempt' if allowed_attempts < 1" do
          api_create_quiz({'hide_results' => 'until_after_last_attempt', 'allowed_attempts' => -1})
          expect(new_quiz.hide_results).not_to eq 'until_after_last_attempt'
        end
      end

      context "show_correct_answers" do
        it "should be set if hide_results is disabled" do
          api_create_quiz({'show_correct_answers' => false, 'hide_results' => nil})
          expect(new_quiz.show_correct_answers).to be_falsey
        end

        it "should be ignored if hide_results is enabled" do
          api_create_quiz({'show_correct_answers' => false, 'hide_results' => 'always'})
          expect(new_quiz.show_correct_answers).to be_truthy
        end
      end

      context 'show_correct_answers_last_attempt' do
        it 'should be settable if show_correct_answers is on and allowed_attempts > 1' do
          api_create_quiz({
            'allowed_attempts' => 2,
            'show_correct_answers' => true,
            'show_correct_answers_last_attempt' => true
          })

          expect(new_quiz.show_correct_answers_last_attempt).to be_truthy
        end

        it 'should be ignored otherwise' do
          api_create_quiz({
            'allowed_attempts' => 2,
            'show_correct_answers' => false,
            'show_correct_answers_last_attempt' => true
          })

          expect(new_quiz.show_correct_answers_last_attempt).to be_falsey,
            'does not work when show_correct_answers is false'

          api_create_quiz({
            'allowed_attempts' => 1,
            'show_correct_answers' => true,
            'show_correct_answers_last_attempt' => true
          })

          expect(new_quiz.show_correct_answers_last_attempt).to be_falsey,
            'does not work when multiple attempts are not specified'
        end
      end

      context "scoring_policy" do
        it "should set scoring policy if allowed_attempts > 1" do
          api_create_quiz({'scoring_policy' => 'keep_latest', 'allowed_attempts' => 3})
          expect(new_quiz.scoring_policy).to eq 'keep_latest'
        end

        it "should not set scoring policy if allowed_attempts == 1" do
          api_create_quiz({'scoring_policy' => 'keep_latest', 'allowed_attempts' => 1})
          expect(new_quiz.scoring_policy).not_to eq 'keep_latest'
        end

        it "should not set scoring policy if allowed_attempts > 1" do
          api_create_quiz({'scoring_policy' => 'keep_latest', 'allowed_attempts' => -1})
          expect(new_quiz.scoring_policy).not_to eq 'keep_latest'
        end
      end

      context "cant_go_back" do
        it "should set cant_go_back if one_question_at_a_time is true" do
          api_create_quiz({'cant_go_back' => true, 'one_question_at_a_time' => true})
          expect(new_quiz.cant_go_back).to be_truthy
        end

        it "should not set cant_go_back if one_question_at_a_time is not true" do
          api_create_quiz({'cant_go_back' => true, 'one_question_at_a_time' => false})
          expect(new_quiz.cant_go_back).not_to be_truthy
        end
      end

      context 'time_limit' do
        it 'should discard negative values' do
          api_create_quiz({'time_limit' => -25})
          expect(new_quiz.time_limit).to be_nil
        end
      end

      context 'allowed_attempts' do
        it 'should discard values less than -1' do
          api_create_quiz({'allowed_attempts' => -25})
          expect(new_quiz.allowed_attempts).to eq 1
        end
      end
    end
  end

  describe "DELETE /courses/:course_id/quizzes/id (destroy)" do
    it "deletes a quiz" do
      teacher_in_course active_all: true
      quiz = course_quiz !!:active
      api_call(:delete, "/api/v1/courses/#{@course.id}/quizzes/#{quiz.id}",
               {controller: 'quizzes/quizzes_api', action: 'destroy',
                format: 'json', course_id: @course.id.to_s,
                id: quiz.id.to_s})
      expect(quiz.reload).to be_deleted
    end
  end

  describe "PUT /courses/:course_id/quizzes/:id (update)" do
    def api_update_quiz(quiz_params, api_params, opts={})
      @quiz ||= @course.quizzes.create!({:title => 'title'}.merge(quiz_params))
      api_call(:put, "/api/v1/courses/#{@course.id}/quizzes/#{@quiz.id}",
              {:controller=>"quizzes/quizzes_api", :action => "update", :format=>"json", :course_id=>"#{@course.id}", :id=>"#{@quiz.id}"},
              {:quiz => api_params}, {}, opts)
    end

    before { teacher_in_course(:active_all => true) }

    let (:updated_quiz) { @course.quizzes.first }
    let (:quiz_params) { {} }

    it "updates quiz attributes" do
      api_update_quiz({'title' => 'old title'}, {'title' => 'new title'})
      expect(updated_quiz.title).to eq 'new title'
    end
    context "jsonapi style request" do

      it "renders in a jsonapi style" do
        @quiz = @course.quizzes.create! title: 'Test Quiz'
        @json = raw_api_call(:put, "/api/v1/courses/#{@course.id}/quizzes/#{@quiz.id}",
                         { :controller=>"quizzes/quizzes_api", :action=>"update", :format=>"json", :course_id=>"#{@course.id}", :id => "#{@quiz.id}"},
                         { quizzes: [{ 'id' => @quiz.id, 'title' => 'blah blah' }] },
                        'Accept' => 'application/vnd.api+json')
        expect(response).to be_success
      end
    end

    it "doesn't allow setting fields not in the whitelist" do
      api_update_quiz({}, {'assignment_id' => 123})
      expect(updated_quiz.assignment_id).not_to eq 123
    end

    it "renders an error when the title is too long" do
      long_title = 'a' * ActiveRecord::Base.maximum_string_length + '!'
      json = api_update_quiz({}, {'title' => long_title}, :expected_status => 400 )
      expect(json).to have_key 'errors'
      expect(updated_quiz.title).to eq 'title'
    end

    context 'lockdown_browser' do
      before :once do
        # require_lockdown_browser, require_lockdown_browser_for_results and
        # require_lockdown_browser_monitor will only return true if the plugin is enabled,
        # so register and enable it for these test
        Canvas::Plugin.register(:example_spec_lockdown_browser, :lockdown_browser, {
                :settings => {:enabled => false}})
        setting = PluginSetting.create!(name: 'example_spec_lockdown_browser')
        setting.settings = {:enabled => true}
        setting.save!
      end

      it 'should allow setting require_lockdown_browser' do
        api_update_quiz({'require_lockdown_browser' => false}, {'require_lockdown_browser' => true})
        expect(updated_quiz.require_lockdown_browser).to be_truthy
      end

      it 'should allow setting require_lockdown_browser_for_results' do
        api_update_quiz({'require_lockdown_browser' => true, 'require_lockdown_browser_for_results' => false}, {'require_lockdown_browser_for_results' => true})
        expect(updated_quiz.require_lockdown_browser_for_results).to be_truthy
      end

      it 'should allow setting require_lockdown_browser_monitor' do
        api_update_quiz({'require_lockdown_browser_monitor' => false}, {'require_lockdown_browser_monitor' => true})
        expect(updated_quiz.require_lockdown_browser_monitor).to be_truthy
      end

      it 'should allow setting lockdown_browser_monitor_data' do
        api_update_quiz({'lockdown_browser_monitor_data' => nil}, {'lockdown_browser_monitor_data' => 'VGVzdCBEYXRhCg=='})
        expect(updated_quiz.lockdown_browser_monitor_data).to eq 'VGVzdCBEYXRhCg=='
      end
    end

    context "draft state changes" do

      it "allows un/publishing an unpublished quiz" do
        api_update_quiz({},{})
        expect(@quiz.reload).not_to be_published # in 'created' state by default
        json = api_update_quiz({}, {published: false})
        expect(json['unpublishable']).to eq true
        expect(@quiz.reload).to be_unpublished
        json = api_update_quiz({}, {published: true})
        expect(json['unpublishable']).to eq true
        expect(@quiz.reload).to be_published
        api_update_quiz({},{published: nil}) # nil shouldn't change published
        expect(@quiz.reload).to be_published

        @quiz.any_instantiation.stubs(:has_student_submissions?).returns true
        json = api_update_quiz({},{}) # nil shouldn't change published
        expect(json['unpublishable']).to eq false

        json = api_update_quiz({}, {published: false}, {expected_status: 400})
        expect(json['errors']['published']).not_to be_nil

        ActiveRecord::Base.reset_any_instantiation!
        expect(@quiz.reload).to be_published
      end

      it "should not lose quiz question count when publishing with draft state" do
        @quiz ||= @course.quizzes.create!(:title => 'title')
        @qq1 = @quiz.quiz_questions.create!(
          question_data: multiple_choice_question_data
        )
        json = api_update_quiz({}, {published: true})
        expect(@quiz.reload).to be_published
        expect(@quiz.question_count).to eq 1
      end
    end

    describe "validations" do
      context "hide_results" do
        it "should set hide_results='until_after_last_attempt' if allowed_attempts > 1" do
          api_update_quiz({'allowed_attempts' => 3}, {'hide_results' => 'until_after_last_attempt'})
          expect(updated_quiz.hide_results).to eq 'until_after_last_attempt'
        end

        it "should not hide_results='until_after_last_attempt' if allowed_attempts == 1" do
          api_update_quiz({'allowed_attempts' => 1}, {'hide_results' => 'until_after_last_attempt'})
          expect(updated_quiz.hide_results).not_to eq 'until_after_last_attempt'
        end

        it "should not hide_results='until_after_last_attempt' if allowed_attempts < 1" do
          api_update_quiz({'allowed_attempts' => -1}, {'hide_results' => 'until_after_last_attempt'})
          expect(updated_quiz.hide_results).not_to eq 'until_after_last_attempt'
        end
      end

      context "show_correct_answers" do
        it "should save show_correct_answers if hide_results is null" do
          api_update_quiz({'hide_results' => nil}, {'show_correct_answers' => false})
          expect(updated_quiz.show_correct_answers).to be_falsey
        end

        it "should not save show_correct_answers if hide_results is not null" do
          api_update_quiz({'hide_results' => 'always'}, {'show_correct_answers' => false})
          expect(updated_quiz.show_correct_answers).to be_truthy
        end
      end

      context "scoring_policy" do
        it "should set scoring policy if allowed_attempts > 1" do
          api_update_quiz({'allowed_attempts' => 3}, {'scoring_policy' => 'keep_latest'})
          expect(updated_quiz.scoring_policy).to eq 'keep_latest'
        end

        it "should not set scoring policy if allowed_attempts == 1" do
          api_update_quiz({'allowed_attempts' => 1}, {'scoring_policy' => 'keep_latest'})
          expect(updated_quiz.scoring_policy).not_to eq 'keep_latest'
        end

        it "should not set scoring policy if allowed_attempts > 1" do
          api_update_quiz({'allowed_attempts' => -1}, {'scoring_policy' => 'keep_latest'})
          expect(updated_quiz.scoring_policy).not_to eq 'keep_latest'
        end
      end

      context "cant_go_back" do
        it "should set cant_go_back if one_question_at_a_time is true" do
          api_update_quiz({'one_question_at_a_time' => true}, {'cant_go_back' => true})
          expect(updated_quiz.cant_go_back).to be_truthy
        end

        it "should not set cant_go_back if one_question_at_a_time is not true" do
          api_update_quiz({'one_question_at_a_time' => false}, {'cant_go_back' => true})
          expect(updated_quiz.cant_go_back).not_to be_truthy
        end
      end

      context 'time_limit' do
        it 'should discard negative values' do
          api_update_quiz({'time_limit' => 10}, {'time_limit' => -25})
          expect(updated_quiz.time_limit).to eq 10
        end
      end

      context 'allowed_attempts' do
        it 'should discard values less than -1' do
          api_update_quiz({'allowed_attempts' => -1}, {'allowed_attempts' => -25})
          expect(updated_quiz.allowed_attempts).to eq -1
        end
      end
    end
  end

  describe "POST /courses/:course_id/quizzes/:id/reorder (reorder)" do
    before :once do
      teacher_in_course(:active_all => true)
      @quiz  = @course.quizzes.create! :title => 'title'
      @question1 = @quiz.quiz_questions.create!(:question_data => {'name' => 'test question 1', 'answers' => [{'id' => 1}, {'id' => 2}], :position => 1})
      @question2 = @quiz.quiz_questions.create!(:question_data => {'name' => 'test question 2', 'answers' => [{'id' => 3}, {'id' => 4}], :position => 2})
      @question3 = @quiz.quiz_questions.create!(:question_data => {'name' => 'test question 3', 'answers' => [{'id' => 5}, {'id' => 6}], :position => 3})
    end

    it "should require authorization" do
      course_with_student_logged_in(:active_all => true)
      course_quiz

      raw_api_call(:post, "/api/v1/courses/#{@course.id}/quizzes/#{@quiz.id}/reorder",
                  {:controller=>"quizzes/quizzes_api", :action => "reorder", :format => "json", :course_id => "#{@course.id}", :id => "#{@quiz.id}"},
                  {:order => [] },
                  {'Accept' => 'application/vnd.api+json'})

      # should be authorization error
      expect(response.code).to eq '401'
    end

    it "should reorder a quiz's questions" do
      raw_api_call(:post, "/api/v1/courses/#{@course.id}/quizzes/#{@quiz.id}/reorder",
                  {:controller=>"quizzes/quizzes_api", :action => "reorder", :format => "json", :course_id => "#{@course.id}", :id => "#{@quiz.id}"},
                  {:order => [{"type" => "question", "id" => @question3.id},
                              {"type" => "question", "id" => @question1.id},
                              {"type" => "question", "id" => @question2.id}] },
                  {'Accept' => 'application/vnd.api+json'})

      # should reorder the quiz questions
      order = @quiz.reload.quiz_questions.active.sort_by{|q| q.position }.map {|q| q.id }
      expect(order).to eq [@question3.id, @question1.id, @question2.id]
    end

    it "should reorder a quiz's questions and groups" do
      @group = @quiz.quiz_groups.create :name => 'Test Group'

      raw_api_call(:post, "/api/v1/courses/#{@course.id}/quizzes/#{@quiz.id}/reorder",
                  {:controller=>"quizzes/quizzes_api", :action => "reorder", :format => "json", :course_id => "#{@course.id}", :id => "#{@quiz.id}"},
                  {:order => [{"type" => "question", "id" => @question3.id},
                              {"type" => "group",    "id" => @group.id},
                              {"type" => "question", "id" => @question1.id},
                              {"type" => "question", "id" => @question2.id}] },
                  {'Accept' => 'application/vnd.api+json'})

      # should reorder group
      expect(@question3.reload.position).to eq 1
      expect(@group.reload.position).to     eq 2
      expect(@question1.reload.position).to eq 3
      expect(@question2.reload.position).to eq 4
    end

    it "should pull questions out of a group to the root quiz" do
      @group = @quiz.quiz_groups.create :name => 'Test Group'
      @group.quiz_questions = [@question1, @question2]

      raw_api_call(:post, "/api/v1/courses/#{@course.id}/quizzes/#{@quiz.id}/reorder",
                  {:controller=>"quizzes/quizzes_api", :action => "reorder", :format => "json", :course_id => "#{@course.id}", :id => "#{@quiz.id}"},
                  {:order => [{"type" => "question", "id" => @question3.id},
                              {"type" => "question", "id" => @question2.id}] },
                  {'Accept' => 'application/vnd.api+json'})

      # should remove items from the group
      order = @group.reload.quiz_questions.active.sort_by{|q| q.position }.map {|q| q.id }
      expect(order).to eq [@question1.id]
    end
  end

  describe "differentiated assignments" do
    def calls_display_quiz(quiz, opts={except: []})
      get_index(quiz.context)
      expect(JSON.parse(response.body).to_s).to include("#{quiz.title}")
      get_show(quiz)
      expect(JSON.parse(response.body).to_s).to include("#{quiz.title}")
    end

    def calls_do_not_show_quiz(quiz)
      get_index(quiz.context)
      expect(JSON.parse(response.body).to_s).not_to include("#{quiz.title}")
      get_show(quiz)
      assert_status(401)
    end

    def get_index(course)
      raw_api_call(:get, "/api/v1/courses/#{course.id}/quizzes",
                   :controller => "quizzes/quizzes_api",
                   :action => "index",
                   :format => "json",
                   :course_id => "#{course.id}")
    end

    def get_show(quiz)
      raw_api_call(:get, "/api/v1/courses/#{quiz.context.id}/quizzes/#{quiz.id}",
                        :controller=>"quizzes/quizzes_api", :action=>"show", :format=>"json", :course_id=>"#{quiz.context.id}", :id => "#{quiz.id}")
    end

    def create_quiz_for_da(opts={})
      @quiz = Quizzes::Quiz.create!({
        context: @course,
        description: 'descript foo',
        only_visible_to_overrides: opts[:only_visible_to_overrides],
        points_possible: rand(1000),
        title: opts[:title]
      })
      @quiz.publish
      @quiz.save!
      @assignment = @quiz.assignment
      @quiz
    end

    before(:once) do
      course_with_teacher(:active_all => true, :user => user_with_pseudonym)
      @student_with_override, @student_without_override= create_users(2, return_type: :record)

      @quiz_with_restricted_access = create_quiz_for_da(title: "only visible to student one", only_visible_to_overrides: true)
      @quiz_visible_to_all = create_quiz_for_da(title: "assigned to all", only_visible_to_overrides: false)

      @course.enroll_student(@student_without_override, :enrollment_state => 'active')
      @section = @course.course_sections.create!(name: "test section")
      student_in_section(@section, user: @student_with_override)
      create_section_override_for_quiz(@quiz_with_restricted_access, {course_section: @section})

      @observer = User.create
      @observer_enrollment = @course.enroll_user(@observer, 'ObserverEnrollment', :section => @course.course_sections.first, :enrollment_state => 'active')
      @observer_enrollment.update_attribute(:associated_user_id, @student_with_override.id)
    end

    context "feature flag on" do
      before {@course.enable_feature!(:differentiated_assignments)}
      it "lets the teacher see all quizzes" do
        @user = @teacher
        [@quiz_with_restricted_access,@quiz_visible_to_all].each{|q| calls_display_quiz(q) }
      end

      it "lets students with visibility see quizzes" do
        @user = @student_with_override
        [@quiz_with_restricted_access,@quiz_visible_to_all].each{|q| calls_display_quiz(q) }
      end

      it 'gives observers the same visibility as their student' do
        @user = @observer
        [@quiz_with_restricted_access,@quiz_visible_to_all].each{|q| calls_display_quiz(q) }
      end

      it 'observers without students see all' do
        @observer_enrollment.update_attribute(:associated_user_id, nil)
        @user = @observer
        [@quiz_with_restricted_access,@quiz_visible_to_all].each{|q| calls_display_quiz(q)}
      end

      it "restricts access to students without visibility" do
        @user = @student_without_override
        calls_do_not_show_quiz(@quiz_with_restricted_access)
        calls_display_quiz(@quiz_visible_to_all)
      end

      it "doesnt show extra assignments with overrides in the index" do
        @quiz_assigned_to_empty_section = create_quiz_for_da(title: "assigned to none", only_visible_to_overrides: true)
        @unassigned_section = @course.course_sections.create!(name: "unassigned section")
        create_section_override_for_quiz(@quiz_assigned_to_empty_section, {course_section: @unassigned_section})

        @user = @student_with_override
        get_index(@course)
        expect(JSON.parse(response.body).to_s).not_to include("#{@quiz_assigned_to_empty_section.title}")
      end
    end

    context "feature flag off" do
      before {@course.disable_feature!(:differentiated_assignments)}
      it "lets the teacher see all quizzes" do
        @user = @teacher
        [@quiz_with_restricted_access,@quiz_visible_to_all].each{|q| calls_display_quiz(q) }
      end

      it "lets students with visibility see quizzes" do
        @user = @student_with_override
        [@quiz_with_restricted_access,@quiz_visible_to_all].each{|q| calls_display_quiz(q) }
      end

      it "does not restrict access to students without visibility" do
        @user = @student_without_override
        [@quiz_with_restricted_access,@quiz_visible_to_all].each{|q| calls_display_quiz(q) }
      end
    end
  end
end
