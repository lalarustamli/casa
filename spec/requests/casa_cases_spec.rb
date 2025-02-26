require "rails_helper"

RSpec.describe "/casa_cases", type: :request do
  let(:organization) { build(:casa_org) }
  let(:valid_attributes) do
    {
      case_number: "1234",
      birth_month_year_youth: pre_transition_aged_youth_age,
      casa_org_id: organization.id
    }
  end
  let(:invalid_attributes) { {case_number: nil, birth_month_year_youth: nil} }
  let(:casa_case) { create(:casa_case, casa_org: organization, case_number: "111") }
  let(:texts) { ["1-New Mandate Text One", "0-New Mandate Text Two"] }
  let(:implementation_statuses) { ["not_implemented", nil] }
  let(:orders_attributes) do
    {
      "0" => {text: texts[0], implementation_status: implementation_statuses[0]},
      "1" => {text: texts[1], implementation_status: implementation_statuses[1]}
    }
  end

  before { sign_in user }

  describe "as an admin" do
    let(:user) { create(:casa_admin, casa_org: organization) }

    describe "GET /index" do
      it "renders a successful response" do
        create(:casa_case)
        get casa_cases_url
        expect(response).to be_successful
      end

      it "shows all my organization's cases" do
        volunteer_1 = create(:volunteer, casa_org: user.casa_org)
        volunteer_2 = create(:volunteer, casa_org: user.casa_org)
        create(:case_assignment, volunteer: volunteer_1)
        create(:case_assignment, volunteer: volunteer_2)

        get casa_cases_url

        expect(response.body).to include(volunteer_1.casa_cases.first.case_number)
        expect(response.body).to include(volunteer_2.casa_cases.first.case_number)
      end

      it "doesn't show other organizations' cases" do
        my_case_assignment = build(:case_assignment, casa_org: user.casa_org)
        different_org = build(:casa_org)
        not_my_case_assignment = build_stubbed(:case_assignment, casa_org: different_org)

        get casa_cases_url

        expect(response.body).to include(my_case_assignment.casa_case.case_number)
        expect(response.body).not_to include(not_my_case_assignment.casa_case.case_number)
      end
    end

    describe "GET /show" do
      it "renders a successful response" do
        get casa_case_url(casa_case)
        expect(response).to be_successful
      end

      it "fails across organizations" do
        other_org = build(:casa_org)
        other_case = create(:casa_case, casa_org: other_org)

        get casa_case_url(other_case)
        expect(response).to be_redirect
        expect(flash[:notice]).to eq("Sorry you are not authorized to perform this action.")
      end

      context "when exporting a csv" do
        subject(:casa_case_show) { get casa_case_path(casa_case, format: :csv) }

        let(:current_time) { Time.now.strftime("%Y-%m-%d") }

        it "generates a csv" do
          casa_case_show

          expect(response).to have_http_status :ok
          expect(response.headers["Content-Type"]).to include "text/csv"
          expect(response.headers["Content-Disposition"]).to include "case-contacts-#{current_time}"
        end

        it "adds the correct headers to the csv" do
          casa_case_show

          csv_headers = ["Internal Contact Number", "Duration Minutes", "Contact Types",
            "Contact Made", "Contact Medium", "Occurred At", "Added To System At", "Miles Driven",
            "Wants Driving Reimbursement", "Casa Case Number", "Creator Email", "Creator Name",
            "Supervisor Name", "Case Contact Notes"]

          csv_headers.each { |header| expect(response.body).to include header }
        end
      end

      context "when exporting a xlsx" do
        subject(:casa_case_show) { get casa_case_path(casa_case, format: :xlsx) }

        let(:current_time) { Time.now.strftime("%Y-%m-%d") }

        it "generates a xlsx file" do
          casa_case_show

          expect(response).to have_http_status :ok
          expect(response.headers["Content-Type"]).to include "application/vnd.openxmlformats"
          expect(response.headers["Content-Disposition"]).to include "case-contacts-#{current_time}"
        end
      end
    end

    describe "GET /new" do
      it "renders a successful response" do
        get new_casa_case_url
        expect(response).to be_successful
      end
    end

    describe "GET /edit" do
      it "render a successful response" do
        get edit_casa_case_url(casa_case)
        expect(response).to be_successful
      end

      it "fails across organizations" do
        other_org = build(:casa_org)
        other_case = create(:casa_case, casa_org: other_org)

        get edit_casa_case_url(other_case)
        expect(response).to be_not_found
      end
    end

    describe "POST /create" do
      context "with valid parameters" do
        it "creates a new CasaCase" do
          expect { post casa_cases_url, params: {casa_case: valid_attributes} }.to change(
            CasaCase,
            :count
          ).by(1)
        end

        it "redirects to the created casa_case" do
          post casa_cases_url, params: {casa_case: valid_attributes}
          expect(response).to redirect_to(casa_case_url(CasaCase.last))
        end

        it "sets fields correctly" do
          post casa_cases_url, params: {casa_case: valid_attributes}
          casa_case = CasaCase.last
          expect(casa_case.casa_org).to eq organization
          expect(casa_case.transition_aged_youth).to be true
        end

        it "also responds as json", :aggregate_failures do
          post casa_cases_url(format: :json), params: {casa_case: valid_attributes}

          expect(response.content_type).to eq("application/json; charset=utf-8")
          expect(response).to have_http_status(:created)
          expect(response.body).to match(valid_attributes[:case_number].to_json)
        end
      end

      it "only creates cases within user's organizations" do
        other_org = build(:casa_org)
        attributes = {
          case_number: "1234",
          transition_aged_youth: true,
          birth_month_year_youth: pre_transition_aged_youth_age,
          casa_org_id: other_org.id
        }

        expect { post casa_cases_url, params: {casa_case: attributes} }.to(
          change { [organization.casa_cases.count, other_org.casa_cases.count] }.from([0, 0]).to([1, 0])
        )
      end

      describe "invalid request" do
        context "with invalid parameters" do
          it "does not create a new CasaCase" do
            expect { post casa_cases_url, params: {casa_case: invalid_attributes} }.to change(
              CasaCase,
              :count
            ).by(0)
          end

          it "renders a successful response (i.e. to display the 'new' template)" do
            post casa_cases_url, params: {casa_case: invalid_attributes}
            expect(response).to be_successful
          end

          it "also respond to json", :aggregate_failures do
            post casa_cases_url(format: :json), params: {casa_case: invalid_attributes}

            expect(response.content_type).to eq("application/json; charset=utf-8")
            expect(response).to have_http_status(:unprocessable_entity)
            expect(response.body).to eq(["Case number can't be blank", "Birth month year youth can't be blank"].to_json)
          end
        end

        context "with case_court_orders_attributes being passed as a parameter" do
          let(:invalid_params) do
            attributes = valid_attributes
            attributes[:case_court_orders_attributes] = orders_attributes
            {casa_case: attributes}
          end

          it "Creates a new CasaCase, but no CaseCourtOrder" do
            expect { post casa_cases_url, params: invalid_params }.to change(
              CasaCase,
              :count
            ).by(1)

            expect { post casa_cases_url, params: invalid_params }.not_to change(
              CaseCourtOrder,
              :count
            )
          end

          it "renders a successful response (i.e. to display the 'new' template)" do
            post casa_cases_url, params: {casa_case: invalid_params}
            expect(response).to be_successful
          end
        end
      end
    end

    describe "PATCH /update" do
      let(:group) { build(:contact_type_group) }
      let(:type1) { create(:contact_type, contact_type_group: group) }
      let(:new_attributes) do
        {
          case_number: "12345",
          case_court_orders_attributes: orders_attributes
        }
      end
      let(:new_attributes2) do
        {
          case_number: "12345",
          case_court_orders_attributes: orders_attributes,
          casa_case_contact_types_attributes: [{contact_type_id: type1.id}]
        }
      end

      context "with valid parameters" do
        it "updates the requested casa_case" do
          patch casa_case_url(casa_case), params: {casa_case: new_attributes2}
          casa_case.reload
          expect(casa_case.case_number).to eq "12345"
          expect(casa_case.case_court_orders[0].text).to eq texts[0]
          expect(casa_case.case_court_orders[0].implementation_status).to eq implementation_statuses[0]
          expect(casa_case.case_court_orders[1].text).to eq texts[1]
          expect(casa_case.case_court_orders[1].implementation_status).to eq implementation_statuses[1]
        end

        it "redirects to the casa_case" do
          patch casa_case_url(casa_case), params: {casa_case: new_attributes2}
          casa_case.reload
          expect(response).to redirect_to(edit_casa_case_path)
        end

        it "displays changed attributes" do
          patch casa_case_url(casa_case), params: {casa_case: new_attributes2}
          expect(flash[:notice]).to eq("CASA case was successfully updated.<ul><li>Changed Case number</li><li>[\"#{type1.name}\"] Contact types added</li><li>2 Court orders added or updated</li></ul>")
        end

        it "also responds as json", :aggregate_failures do
          patch casa_case_url(casa_case, format: :json), params: {casa_case: new_attributes2}

          expect(response.content_type).to eq("application/json; charset=utf-8")
          expect(response).to have_http_status(:ok)
          expect(response.body).to match(new_attributes2[:case_number].to_json)
        end
      end

      context "with invalid parameters" do
        it "renders a successful response displaying the edit template" do
          patch casa_case_url(casa_case), params: {casa_case: invalid_attributes}
          expect(response).to be_successful
        end

        it "also responds as json", :aggregate_failures do
          patch casa_case_url(casa_case, format: :json), params: {casa_case: invalid_attributes}

          expect(response.content_type).to eq("application/json; charset=utf-8")
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to match(["Case number can't be blank"].to_json)
        end
      end

      describe "court orders" do
        context "when the user tries to make an existing order empty" do
          let(:orders_updated) do
            {
              case_court_orders_attributes: {
                "0" => {
                  text: "New Mandate Text One Updated",
                  implementation_status: :not_implemented
                },
                "1" => {
                  text: ""
                }
              }
            }
          end

          before do
            patch casa_case_url(casa_case), params: {casa_case: new_attributes2}
            casa_case.reload

            orders_updated[:case_court_orders_attributes]["0"][:id] = casa_case.case_court_orders[0].id
            orders_updated[:case_court_orders_attributes]["1"][:id] = casa_case.case_court_orders[1].id
          end

          it "does not update the first court order" do
            expect { patch casa_case_url(casa_case), params: {casa_case: orders_updated} }.not_to(
              change { casa_case.reload.case_court_orders[0].text }
            )
          end

          it "does not update the second court order" do
            expect { patch casa_case_url(casa_case), params: {casa_case: orders_updated} }.not_to(
              change { casa_case.reload.case_court_orders[1].text }
            )
          end
        end
      end

      it "does not update across organizations" do
        other_org = build(:casa_org)
        other_casa_case = create(:casa_case, case_number: "abc", casa_org: other_org)

        expect { patch casa_case_url(other_casa_case), params: {casa_case: new_attributes} }.not_to(
          change { other_casa_case.reload.case_number }
        )
      end
    end

    describe "PATCH /casa_cases/:id/deactivate" do
      let(:casa_case) { create(:casa_case, :active, casa_org: organization, case_number: "111") }
      let(:params) { {id: casa_case.id} }

      it "deactivates the requested casa_case" do
        patch deactivate_casa_case_path(casa_case), params: params
        casa_case.reload
        expect(casa_case.active).to eq false
      end

      it "redirects to the casa_case" do
        patch deactivate_casa_case_path(casa_case), params: params
        casa_case.reload
        expect(response).to redirect_to(edit_casa_case_path)
      end

      it "flashes success message" do
        patch deactivate_casa_case_path(casa_case), params: params
        expect(flash[:notice]).to include("Case #{casa_case.case_number} has been deactivated.")
      end

      it "fails across organizations" do
        other_org = build(:casa_org)
        other_casa_case = create(:casa_case, casa_org: other_org)

        patch deactivate_casa_case_path(other_casa_case), params: params
        expect(response).to be_not_found
      end

      it "also responds as json", :aggregate_failures do
        patch deactivate_casa_case_path(casa_case, format: :json), params: params

        expect(response.content_type).to eq("application/json; charset=utf-8")
        expect(response).to have_http_status(:ok)
        expect(response.body).to match("Case #{casa_case.case_number} has been deactivated.")
      end

      context "when deactivation fails" do
        before do
          allow_any_instance_of(CasaCase).to receive(:deactivate).and_return(false)
        end

        it "does not deactivate the requested casa_case" do
          patch deactivate_casa_case_path(casa_case), params: params
          casa_case.reload
          expect(casa_case.active).to eq true
        end

        it "also responds as json", :aggregate_failures do
          patch deactivate_casa_case_path(casa_case, format: :json), params: params

          expect(response.content_type).to eq("application/json; charset=utf-8")
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to match([].to_json)
        end
      end
    end

    describe "PATCH /casa_cases/:id/reactivate" do
      let(:casa_case) { create(:casa_case, :inactive, casa_org: organization, case_number: "111") }
      let(:params) { {id: casa_case.id} }

      it "reactivates the requested casa_case" do
        patch reactivate_casa_case_path(casa_case), params: params
        casa_case.reload
        expect(casa_case.active).to eq true
      end

      it "redirects to the casa_case" do
        patch reactivate_casa_case_path(casa_case), params: params
        casa_case.reload
        expect(response).to redirect_to(edit_casa_case_path)
      end

      it "flashes success message" do
        patch reactivate_casa_case_path(casa_case), params: params
        expect(flash[:notice]).to include("Case #{casa_case.case_number} has been reactivated.")
      end

      it "fails across organizations" do
        other_org = create(:casa_org)
        other_casa_case = create(:casa_case, casa_org: other_org)

        patch reactivate_casa_case_path(other_casa_case), params: params
        expect(response).to be_not_found
      end

      it "also responds as json", :aggregate_failures do
        patch reactivate_casa_case_path(casa_case, format: :json), params: params

        expect(response.content_type).to eq("application/json; charset=utf-8")
        expect(response).to have_http_status(:ok)
        expect(response.body).to match("Case #{casa_case.case_number} has been reactivated.")
      end

      context "when reactivation fails" do
        before do
          allow_any_instance_of(CasaCase).to receive(:reactivate).and_return(false)
        end

        it "does not reactivate the requested casa_case" do
          patch deactivate_casa_case_path(casa_case), params: params
          casa_case.reload
          expect(casa_case.active).to eq false
        end

        it "also responds as json", :aggregate_failures do
          patch reactivate_casa_case_path(casa_case, format: :json), params: params

          expect(response.content_type).to eq("application/json; charset=utf-8")
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to match([].to_json)
        end
      end
    end
  end

  describe "as a volunteer" do
    let(:user) { create(:volunteer, casa_org: organization) }
    let!(:case_assignment) { create(:case_assignment, volunteer: user, casa_case: casa_case) }

    describe "GET /new" do
      it "denies access and redirects elsewhere" do
        get new_casa_case_url

        expect(response).not_to be_successful
        expect(flash[:notice]).to match(/you are not authorized/)
      end
    end

    describe "GET /edit" do
      it "render a successful response" do
        get edit_casa_case_url(casa_case)
        expect(response).to be_successful
      end

      it "fails across organizations" do
        other_org = build(:casa_org)
        other_case = create(:casa_case, casa_org: other_org)

        get edit_casa_case_url(other_case)
        expect(response).to be_not_found
      end
    end

    describe "PATCH /update" do
      let(:new_attributes) {
        {
          case_number: "12345",
          court_report_status: :submitted,
          case_court_orders_attributes: orders_attributes
        }
      }

      context "with valid parameters" do
        it "updates permitted fields" do
          patch casa_case_url(casa_case), params: {casa_case: new_attributes}
          casa_case.reload

          expect(casa_case.court_report_submitted?).to be_truthy

          # Not permitted
          expect(casa_case.case_number).to eq "111"
          expect(casa_case.case_court_orders.size).to be 2
        end

        it "redirects to the casa_case" do
          patch casa_case_url(casa_case), params: {casa_case: new_attributes}
          expect(response).to redirect_to(edit_casa_case_path(casa_case))
        end

        it "also responds as json", :aggregate_failures do
          patch casa_case_url(casa_case, format: :json), params: {casa_case: new_attributes}

          expect(response.content_type).to eq("application/json; charset=utf-8")
          expect(response).to have_http_status(:ok)
          expect(response.body).not_to match(new_attributes[:case_number].to_json)
        end
      end

      it "does not update across organizations" do
        other_org = build(:casa_org)
        other_casa_case = create(:casa_case, case_number: "abc", casa_org: other_org)

        expect { patch casa_case_url(other_casa_case), params: {casa_case: new_attributes} }.not_to(
          change { other_casa_case.reload.attributes }
        )
      end
    end

    describe "GET /index" do
      it "shows only cases assigned to user" do
        mine = build(:casa_case, casa_org: organization, case_number: SecureRandom.hex(32))
        other = build(:casa_case, casa_org: organization, case_number: SecureRandom.hex(32))

        user.casa_cases << mine

        get casa_cases_url

        expect(response).to be_successful
        expect(response.body).to include(mine.case_number)
        expect(response.body).not_to include(other.case_number)
      end

      it "shows only duties from the user" do
        mine = build(:other_duty)
        other = build(:other_duty)

        user.other_duties << mine

        get casa_cases_url

        expect(response).to be_successful
        expect(response.body).to include(mine.decorate.truncate_notes)
        expect(response.body).not_to include(other.decorate.truncate_notes)
      end
    end

    describe "PATCH /casa_cases/:id/deactivate" do
      let(:casa_case) { build(:casa_case, :active, casa_org: organization, case_number: "111") }
      let(:params) { {id: casa_case.id} }

      it "does not deactivate the requested casa_case" do
        patch deactivate_casa_case_path(casa_case), params: params
        casa_case.reload
        expect(casa_case.active).to eq true
      end
    end

    describe "PATCH /casa_cases/:id/reactivate" do
      let(:casa_case) { build(:casa_case, :inactive, casa_org: organization, case_number: "111") }
      let(:params) { {id: casa_case.id} }

      it "does not deactivate the requested casa_case" do
        patch deactivate_casa_case_path(casa_case), params: params
        casa_case.reload
        expect(casa_case.active).to eq false
      end
    end
  end

  describe "as a supervisor" do
    let(:user) { create(:supervisor, casa_org: organization) }

    describe "GET /new" do
      it "renders a successful response" do
        get new_casa_case_url
        expect(response).to be_successful
      end
    end

    describe "GET /edit" do
      it "render a successful response" do
        get edit_casa_case_url(casa_case)
        expect(response).to be_successful
      end

      it "fails across organizations" do
        other_org = build(:casa_org)
        other_case = create(:casa_case, casa_org: other_org)

        get edit_casa_case_url(other_case)
        expect(response).to be_not_found
      end
    end

    describe "PATCH /update" do
      let(:group) { build(:contact_type_group) }
      let(:type1) { create(:contact_type, contact_type_group: group) }
      let(:new_attributes) do
        {
          case_number: "12345",
          court_report_status: :completed,
          case_court_orders_attributes: orders_attributes
        }
      end
      let(:new_attributes2) do
        {
          case_number: "12345",
          court_report_status: :completed,
          case_court_orders_attributes: orders_attributes,
          casa_case_contact_types_attributes: [{contact_type_id: type1.id}]
        }
      end

      context "with valid parameters" do
        it "updates fields (except case_number)" do
          patch casa_case_url(casa_case), params: {casa_case: new_attributes2}
          casa_case.reload

          expect(casa_case.case_number).to eq "111"
          expect(casa_case.court_report_completed?).to be true

          expect(casa_case.case_court_orders[0].text).to eq texts[0]
          expect(casa_case.case_court_orders[0].implementation_status).to eq implementation_statuses[0]

          expect(casa_case.case_court_orders[1].text).to eq texts[1]
          expect(casa_case.case_court_orders[1].implementation_status).to eq implementation_statuses[1]
        end

        it "redirects to the casa_case" do
          patch casa_case_url(casa_case), params: {casa_case: new_attributes2}
          expect(response).to redirect_to(edit_casa_case_path(casa_case))
        end

        it "also responds as json", :aggregate_failures do
          patch casa_case_url(casa_case, format: :json), params: {casa_case: new_attributes2}

          expect(response.content_type).to eq("application/json; charset=utf-8")
          expect(response).to have_http_status(:ok)
          expect(response.body).not_to match(new_attributes[:case_number].to_json)
        end
      end

      it "does not update across organizations" do
        other_org = build(:casa_org)
        other_casa_case = create(:casa_case, case_number: "abc", casa_org: other_org)

        expect { patch casa_case_url(other_casa_case), params: {casa_case: new_attributes} }.not_to(
          change { other_casa_case.reload.attributes }
        )
      end
    end

    describe "GET /index" do
      it "renders a successful response" do
        build_stubbed(:casa_case)
        get casa_cases_url
        expect(response).to be_successful
      end
    end

    describe "PATCH /casa_cases/:id/deactivate" do
      let(:casa_case) { create(:casa_case, :active, casa_org: organization, case_number: "111") }
      let(:params) { {id: casa_case.id} }

      it "does not deactivate the requested casa_case" do
        patch deactivate_casa_case_path(casa_case), params: params
        casa_case.reload
        expect(casa_case.active).to eq true
      end
    end

    describe "PATCH /casa_cases/:id/reactivate" do
      let(:casa_case) { create(:casa_case, :inactive, casa_org: organization, case_number: "111") }
      let(:params) { {id: casa_case.id} }

      it "does not deactivate the requested casa_case" do
        patch deactivate_casa_case_path(casa_case), params: params
        casa_case.reload
        expect(casa_case.active).to eq false
      end
    end
  end
end
