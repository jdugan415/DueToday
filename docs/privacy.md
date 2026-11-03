---
layout: default
title: DueToday Privacy Policy
---

# DueToday Privacy Policy

- **Effective date:** November 3, 2026
- **App:** DueToday for Android (`com.duetoday.app`)
- **Developer:** DueToday Team
- **Contact:** [duetoday.app@gmail.com](mailto:duetoday.app@gmail.com)

DueToday turns a course syllabus into a list of assignments and lets you add
due dates to your phone's calendar. This page explains what data the app
handles, where it goes, and how to remove it. There are no accounts, no ads,
no analytics, and no third-party tracking.

## Data stored on your device

Your assignments, courses, and settings are saved in the app's private storage
on your phone. They never leave the device unless you use one of the features
described below. Uninstalling the app deletes them.

## Syllabus text and PDF uploads

When you paste syllabus text or upload a syllabus PDF, the app sends it over
HTTPS to the DueToday server so the server can find dates, titles, and
weights. The text is processed in memory and the results are returned to you.
It is not stored in a database, not logged, and not used for anything other
than that request. Uploads larger than 1 MB may pass through a temporary file
on the server, which is deleted when the request finishes.

## Shared courses

If you tap **Share** on a course, the app sends that course to our server and
the server stores it under a random 5-character code so classmates can import
it. Stored fields: course code, course name, the time the course was shared,
and for each assignment its title, type, due date and time, weight, points,
priority, and notes. Anyone who has the code can read this data, so do not put
personal information in assignment notes. Shared courses are kept until you
ask us to delete them. Nothing is stored on the server unless you tap Share.

## Calendar, exports, and file access

Adding an assignment to your calendar hands a pre-filled event to your
calendar app; DueToday has no calendar permission and cannot read or write
your calendar. Exports (calendar, Markdown, CSV) go through the Android share
sheet to the app you choose. Choosing a PDF uses the Android document picker,
so the app has no storage permission and only receives the file you pick.

## Server logs and rate limiting

Like any web service, our hosting provider records the IP address, time, and
path of each request in short-lived server logs used for security and
troubleshooting. The API also keeps IP addresses in memory for up to one hour
to limit abuse. We do not link this information to you or to any syllabus
content.

## Service providers

The API runs on Render and shared courses are stored in a Supabase Postgres
database. Both process data on our behalf under their own privacy policies.

## Children

DueToday is intended for college students and is not directed at children
under 13.

## Your choices and deleting data

- **Local data:** delete assignments or courses in the app, or uninstall it.
- **Shared courses:** email the contact address above with the 5-character
  share code and we will delete it. DueToday has no accounts, so we cannot
  verify who originally shared a course and will honor a request from anyone
  holding the code.

## Changes to this policy

We will post changes on this page and update the effective date. The full
history is in the project's GitHub repository.