#!/usr/bin/env python
# -*- coding: utf-8 -*-

import smtplib, re, email, os
from email.MIMEText import MIMEText
from pprint import pprint


FROM = re.compile(r'^From: .*', re.MULTILINE)
TO = re.compile(r'^To: .*', re.MULTILINE)

Smtp = "smtp.mail.ru"
#Pwd = "vbhevjb[yju"
#From = "lucifera.satan@mail.ru"

Pwd = "pol2naqZaschita"
From = "darviarush@mail.ru"
To = "darviarush@ya.ru"

for x in os.walk("msg"):
	pass

x = list(x[2])
x.sort(key = lambda i: int(i))

i = 0
for file in x:
	msg1 = email.message_from_file(open("msg/%s" % file, "rb"))
	
	for msg in msg1.walk():
		
		if i<456:
			i+=1
			continue
		
		msg2 = msg
		msg = msg.as_string()
		
		if msg2["Content-Type"] == "message/rfc822":
			pos = msg.index("\n\n")
			msg = msg[pos+2:]
			print "\n\nmessage/rfc822\n"
			
		
		g1 = FROM.search(msg)
		if g1: msg = FROM.sub("From: "+From, msg, 1)
		else: msg = "From: %s\n%s" % (From, msg)
		
		g2 = TO.search(msg)
		if g2: msg = TO.sub("To: "+To, msg, 1)
		else: msg = "To: %s\n%s" % (To, msg)
		
		pos = msg.index("\n\n")
		print file, i, msg[: pos+2]


		s = smtplib.SMTP(Smtp, 25)
		s.ehlo()
		s.starttls()
		s.ehlo()
		s.login(From, Pwd)
		s.sendmail(From, To, msg)
		s.quit()
		i += 1

print 
print i
print
