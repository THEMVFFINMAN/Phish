import os
from os import listdir
from os.path import isfile, join
import time
import sqlite3 as lite
import sys

path_to_watch = "C:\Users\josh\Desktop\Tor Browser"
db_filename = "password_files.db"
table_name = "files_db"
sleep = 10
queue = []

def setup_database():
    db_is_new = not os.path.exists(db_filename)
    conn = lite.connect(db_filename)
    c = conn.cursor()

    c.execute('''CREATE TABLE IF NOT EXISTS {}
            (file TEXT UNIQUE, type TEXT, status TEXT)'''.format(table_name))

    print "[+] Connected to Table {} Successfully".format(table_name)

    return c


def get_files():
    fonly_files = [f for f in listdir(path_to_watch) if isfile(join(path_to_watch,f))]

    for i in range(len(fonly_files)):
        fonly_files[i] = fonly_files[i].split(".")

    return fonly_files


def initial_insert(c):
    only_files = get_files()

    for file in only_files:
        c.execute("INSERT INTO {} VALUES('{}','{}','{}')".format(table_name, file[0], file[1], "brandnew"))

        
def print_database(c):        
    c.execute('SELECT * FROM {}'.format(table_name))
    result = c.fetchall()

    for row in result:
        print "[+] File: {:20s} Ext: {:10s} Status: {}".format(row[0], row[1], row[2])
            


def add_new_files(c):
    only_files = get_files()

    for file in only_files:
        c.execute("INSERT OR IGNORE INTO {} VALUES('{}','{}','{}')".format(table_name, file[0], file[1], "brandnew"))


def update_value(c, file, change):
    c.execute('UPDATE {} SET status="{}" WHERE file="{}"'.format(table_name, change, file))


def queue_files(c):
    c.execute('SELECT * FROM {} where status = "brandnew"'.format(table_name))
    result = c.fetchall()

    if result:
        for row in result:
            queue.append((row[0],row[1]))

        print "[+] Added File: {:20s} Ext: {:10s} Status: {}".format(row[0], row[1], row[2])

        c.execute('UPDATE {} SET status="{}" WHERE status="{}"'.format(table_name, "new", "brandnew"))

def main():
    print "Using Path: {}".format(path_to_watch)
    c = setup_database()
    initial_insert(c)

    while(1):  
        add_new_files(c)
        queue_files(c)
        print "[+] Sleeping for {} seconds".format(sleep)
        time.sleep(sleep)

if __name__ == "__main__":
    main()
