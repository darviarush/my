#!/usr/bin/env python
# -*- coding: utf-8 -*-

import poplib, codecs
from pprint import pprint

M = poplib.POP3('pop3.mail.ru')
M.user("lucifera.satan@mail.ru")
M.pass_("vbhevjb[yju")
numMessages = len(M.list()[1])
f = open("msg.txt", "wb")
for i in xrange(1, numMessages+1):
	retr = M.retr(i)
	print "%i/%i\t\t%s" % (i, numMessages, retr[1][0])
	
	for j in retr[1]:
		print >> f, j
	f.close()