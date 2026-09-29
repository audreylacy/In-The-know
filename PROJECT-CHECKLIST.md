# In The Know completion checklist

This project is a static HTML app using Supabase. Follow the sections in order.

## Start here: what to do now

1. Run the updated `supabase-schema.sql` in your Supabase project's **SQL Editor**. This is required for school joining and school-wide announcements.
2. Check that the required tables and functions listed in section 1 appear in Supabase.
3. Refresh the app, then test one teacher and one student account by following sections 6 and 7.
4. Deploy the app to an HTTPS website by following section 5 before testing on phones or Chromebooks.
5. Treat background push as a later add-on. The app does not yet send system push alerts after the browser is closed; section 8 explains what is missing.

## 1. Supabase database

1. Open the Supabase project connected to the app.
2. Open **SQL Editor** and create a new query.
3. Open the local `supabase-schema.sql` file, copy all of its SQL, and paste it into the query. If you ran an earlier version, run this updated full file again; it adds the school announcements table, policies, Realtime publication, and school-join function.
4. Click **Run**.
5. Confirm that these tables exist in **Table Editor**:
   - profiles
   - schools
   - classes
   - class_members
   - notifications
   - school_notifications
   - calendar_events
   - push_subscriptions
6. Confirm that `profiles` contains `username`.
7. Confirm that the function `resolve_login_email` exists under Database Functions.
8. Confirm that the function `join_school_by_code` exists under Database Functions.
9. In **Database > Publications** or the Realtime settings, confirm `school_notifications` is included in `supabase_realtime`. The updated SQL attempts to add it automatically.

Do not create a second copy of the schema. The SQL uses `if not exists` and can be run again when the file is updated.

## 2. Authentication settings

1. In Supabase, open **Authentication > Providers**.
2. Enable Email if users will create accounts with email and password.
3. Decide whether email confirmation is required. If it is enabled, users must confirm their email before the first sign-in.
4. If using Google, configure the Google provider and add the exact Supabase callback URL shown by Supabase.
5. Add the deployed HTTPS site URL under **Authentication > URL Configuration**.

The app uses email only during account creation. Returning users sign in with username and password. Users choose Student or Teacher only while creating an account; they do not choose a role during later sign-ins. The dashboard uses the saved `profiles.role` value.

## 3. Existing accounts

For each existing user:

1. Open **Table Editor > profiles**.
2. Enter a unique lowercase username.
3. Check that `role` is exactly `student` or `teacher`.
4. Check that teachers have `school_name` and `school_code`.

A username cannot be shared by two accounts.

## 4. Test locally before deployment

A local server is useful for basic UI testing:

```text
python -m http.server 8000
```

Open `http://localhost:8000` on the same computer. Local HTTP is not enough for production push notifications.

## 5. Deploy without npm

Use a hosting dashboard that supports static files, such as Netlify Drop, GitHub Pages, or Vercel. No Node.js or npm account is needed for static hosting:

1. Upload `index.html`, `style.css`, and `service-worker.js`.
2. Keep all three files in the same published folder.
3. Open the HTTPS deployment URL.
4. Add that URL to Supabase Authentication URL Configuration.
5. Test the app from the deployed URL, not only from localhost.

## 6. Basic account tests

Use separate browser profiles for the teacher and student accounts.

### Teacher test

- Create a teacher account with a unique username.
- Select `I'm a teacher` during account creation.
- Complete full name, school name, and school code.
- Sign out and sign back in with username and password without selecting a role.
- Confirm the teacher workspace appears.
- Create a class with a unique class code.
- Confirm the class appears in `classes`.
- Create a second teacher account using the existing school code and confirm it joins that school instead of creating a duplicate.

### Student test

- Create a student account with a different username.
- Select `I'm a student` during account creation.
- Complete the student profile.
- Sign out and sign back in with username and password without selecting a role.
- Confirm the student dashboard appears.
- Click **Join school**, enter the teacher's school code, and confirm the school is accepted.
- Join the teacher class using its class code.
- Confirm a row appears in `class_members`.
- Confirm the student's `profiles.school_code` matches the school's code.

### School announcement test

- With the teacher account, choose **Entire school** in the announcement form.
- Send an announcement.
- Confirm a row appears in `school_notifications`.
- With the student account that joined the school, confirm the announcement appears in the dashboard.
- Keep the student dashboard open while sending to confirm the update arrives live.
- Repeat with a second student account at the same school and confirm both dashboards receive the announcement.
- Join a different school with a test account and confirm that account does not see the first school's announcement.

### Role-isolation test

- Sign in as a student and verify teacher controls are hidden.
- Sign in as a teacher and verify the class-join control is hidden; the **Join school** control is available to both roles.
- Confirm the role buttons are hidden on the sign-in screen.
- Confirm the correct dashboard follows the saved `profiles.role`, even if the browser previously used a different account.

## 7. Notification tests currently supported

The app currently supports in-app updates and browser notifications while the page is open:

1. Student opens the deployed HTTPS app.
2. Student clicks **Enable alerts** and chooses **Allow**.
3. Teacher sends a notification to a class.
4. Student confirms the message appears in the dashboard.
5. Confirm a row appears in `notifications`.

School-wide announcements are stored in `school_notifications` and delivered to profiles whose `school_code` matches the school. Supabase Realtime updates dashboards while they are open. This alone does not guarantee system notifications when the Chromebook browser is closed.

This is not background push delivery. A browser notification may appear while the page is open and permission is granted, but delivery is not guaranteed after the browser is closed.

## 8. Real background push add-on

This is optional until you need system notifications while the browser is closed. It requires a VAPID key pair and a server-side sender. npm is not required locally.

1. Generate a VAPID key pair using a trusted browser-based VAPID generator.
2. Put only the public key in `index.html`, replacing `YOUR_VAPID_PUBLIC_KEY_HERE`.
3. Keep the private key secret. Never put it in `index.html`.
4. Create a Supabase Edge Function using the Supabase dashboard editor.
5. Add the private VAPID key and contact email as Edge Function secrets.
6. Make the Edge Function read `push_subscriptions` for the intended recipients: members of the selected class or profiles belonging to the selected school.
7. Send the Web Push payload containing `title`, `message`, and a tag.
8. Call the Edge Function after a teacher creates a notification.
9. Remove expired subscriptions when a push provider returns an expired or invalid endpoint.

The Edge Function is required because a browser must never contain the VAPID private key.

## 9. Background push test

Do this only after the Edge Function sender has been built, secrets have been set, and the app is deployed on HTTPS.

- Student allows notifications on the deployed HTTPS site.
- Confirm a row exists in `push_subscriptions` for that student.
- Close the student tab or browser window.
- Teacher sends a notification.
- Confirm the Chromebook displays a system notification.
- Click the notification and confirm the app opens.
- Test a second student device.
- Test an invalid or expired subscription and confirm it is removed without breaking delivery to other students.

## 10. Security checks before sharing the app

- Never expose a Supabase service-role key in HTML or browser JavaScript.
- Never expose the VAPID private key in HTML or browser JavaScript.
- Keep Row Level Security enabled on every public table.
- Verify students can read only their classes, memberships, notifications, and profiles allowed by the policies.
- Verify teachers can manage only their own classes and notifications.
- Verify a teacher can send school announcements only to their own school.
- Verify a user from another school cannot read school announcements or subscribe to that school's Realtime updates.
- Protect username login lookup from abuse; it currently resolves usernames to account emails and should not be exposed without suitable rate limiting or a server-side authentication design before a public launch.
- Use HTTPS for the public site.
- Do not use real student information during testing.

## 11. Launch checklist

The app is ready for a small supervised pilot when:

- Supabase schema ran successfully.
- Teacher and student username login both work.
- The correct dashboard appears for each saved role.
- A student can join a teacher class.
- A student or additional teacher can join the correct school using its school code.
- A teacher can send a notification.
- Students at that school see a school announcement in the dashboard while online.
- HTTPS deployment works on a Chromebook.
- School separation and role security checks pass.

The app is ready for closed-browser push testing only after all of these are also true:

- Push subscriptions are saved.
- The Edge Function sends a background notification successfully.
- A real Chromebook receives an alert with the app closed.
