from os import listdir
from os.path import isfile, join
import threading
import os
import Queue
import time
import sqlite3 as lite
import sys

path_to_watch = "C:\Users\josh\Desktop\Tor Browser"
db_filename = "password_files.db"
table_name = "files_db"
sleep = 10
queue = Queue.Queue()
cracking = False

def setup_database():
    db_is_new = not os.path.exists(db_filename)
    conn = lite.connect(db_filename)
    c = conn.cursor()

    c.execute('''CREATE TABLE IF NOT EXISTS {}
            (file TEXT UNIQUE, type TEXT, status TEXT)'''.format(table_name))

    print "[+] Connected to Table {} Successfully".format(table_name)

    return c, conn


def get_files():
    fonly_files = [f for f in listdir(path_to_watch) if isfile(join(path_to_watch,f))]

    for i in range(len(fonly_files)):
        fonly_files[i] = fonly_files[i].split(".")

    return fonly_files


def insert(c):
    only_files = get_files()

    for file in only_files:
        c.execute("INSERT OR IGNORE INTO {} VALUES('{}','{}','{}')".format(table_name, file[0], file[1], "new"))

        
def print_database(c):        
    c.execute('SELECT * FROM {}'.format(table_name))
    result = c.fetchall()

    for row in result:
        print "[+] File: {:20s} Ext: {:10s} Status: {}".format(row[0], row[1], row[2])


def update_value(c, change, original):
    c.execute('UPDATE {} SET status="{}" WHERE status="{}"'.format(table_name, change, original))


def queue_files(c):
    c.execute('SELECT * FROM {} where status = "new"'.format(table_name))
    result = c.fetchall()

    if result:
        for row in result:
            queue.put((row[0],row[1]))

        print "[+] Added File: {:20s} Ext: {:10s} Status: {}".format(row[0], row[1], row[2])

        update_value(c, "queued", "new")

def wait():
    print "[+] Sleeping for {} seconds".format(sleep)
    time.sleep(sleep)


def cracker_jack():
    top = queue.get()
    print "[+] Starting crack on {}.{}".format(top[0], top[1])
    
    if top[1] == "ntlm":
        print "got eeem"

def main():
    print "Using Path: {}".format(path_to_watch)
    c, conn = setup_database()
    insert(c)
    
    try:
        while(1):
            insert(c)
            queue_files(c)

            if not queue.empty():
                print queue
                cracker_jack()
            else:
                wait()
    except (KeyboardInterrupt, SystemExit):
        print "[+] Exit detected, saving and closing database"
        conn.commit()
        conn.close()
            
            

if __name__ == "__main__":
    main()
