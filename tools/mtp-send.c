#include <libmtp.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/stat.h>
int main(int argc,char**argv){ uint32_t parent=strtoul(argv[3],0,10);
 LIBMTP_Init(); LIBMTP_mtpdevice_t*d=LIBMTP_Get_First_Device(); if(!d){puts("no device");return 1;}
 LIBMTP_Get_Storage(d,0);
 LIBMTP_file_t*l=LIBMTP_Get_Files_And_Folders(d,d->storage->id,parent);
 for(LIBMTP_file_t*f=l;f;f=f->next){ printf("existing: %u %s %llu\n",f->item_id,f->filename,(unsigned long long)f->filesize);
   if(f->filetype!=LIBMTP_FILETYPE_FOLDER && !strcasecmp(f->filename,argv[2])){printf("deleting old %u -> %d\n",f->item_id,LIBMTP_Delete_Object(d,f->item_id));}}
 struct stat s; stat(argv[1],&s);
 LIBMTP_file_t*f=LIBMTP_new_file_t(); f->filename=strdup(argv[2]); f->filesize=s.st_size; f->filetype=LIBMTP_FILETYPE_UNKNOWN; f->parent_id=parent; f->storage_id=d->storage->id;
 int r=LIBMTP_Send_File_From_File(d,argv[1],f,NULL,NULL); printf("send -> %d, new id %u\n",r,f->item_id);
 if(r){LIBMTP_Dump_Errorstack(d);}
 l=LIBMTP_Get_Files_And_Folders(d,d->storage->id,parent);
 for(LIBMTP_file_t*g=l;g;g=g->next) printf("after: %u %s %llu\n",g->item_id,g->filename,(unsigned long long)g->filesize);
 LIBMTP_Release_Device(d); return r;}
