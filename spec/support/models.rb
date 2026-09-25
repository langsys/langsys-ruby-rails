# frozen_string_literal: true

require "active_model"

# Sample ActiveModel forms for the server-message specs (MSG-1..11).
class Signup
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email, :string
  attribute :age, :integer
  attribute :tags
  attribute :starts_on, :date
  attribute :password, :string
  attribute :password_confirmation, :string

  validates :email, presence: true, length: { minimum: 5 }, format: { with: /@/ }
  validates :age, numericality: { greater_than_or_equal_to: 18, less_than: 130 }
  validates :tags, length: { maximum: 2 }
  validates :starts_on, comparison: { greater_than: Date.new(2026, 1, 1) }
  validates :password, confirmation: true
end

class SignupWithCustomRule < Signup
  def self.name = "SignupWithCustomRule"

  validate :not_on_a_holiday

  def not_on_a_holiday = nil
end

class SignupWithDeclaredRule < SignupWithCustomRule
  def self.name = "SignupWithDeclaredRule"

  def self.langsys_message_templates
    { starts_on: ["The start date cannot be a holiday."] }
  end
end

class Unlabelled
  include ActiveModel::Model

  attr_accessor :cc_number

  validates :cc_number, presence: true
end
