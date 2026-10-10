namespace :admin do
  desc "Create the admin account, or set a new password for it (asks for the password; never pass it as an argument)"
  task create: :environment do
    require "io/console"

    email = ENV["EMAIL"].presence || ($stdout.print("Email address: ") && $stdin.gets.to_s.strip)
    handle = ENV["HANDLE"].presence || ($stdout.print("Handle, as decisions will show it (human:<handle>): ") && $stdin.gets.to_s.strip)
    password = $stdin.getpass("Password (12 characters or more): ")

    user = User.find_or_initialize_by(email_address: email.strip.downcase)
    if user.update(handle:, password:)
      puts "#{user.previously_new_record? ? 'Created' : 'Updated'} #{user.email_address}. Decisions are recorded as #{user.actor}."
    else
      abort user.errors.full_messages.to_sentence
    end
  end
end
