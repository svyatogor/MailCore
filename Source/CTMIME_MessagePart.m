/*
 * MailCore
 *
 * Copyright (C) 2007 - Matt Ronge
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the MailCore project nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */


#import "CTMIME_MessagePart.h"
#import <libetpan/libetpan.h>
#import "MailCoreTypes.h"
#import "CTMIMEFactory.h"
#import "MailCoreUtilities.h"


static inline struct imap_session_state_data *
get_session_data(mailmessage * msg)
{
    return msg->msg_session->sess_data;
}


static void download_progress_callback(size_t current, size_t maximum, void * context) {
    CTProgressBlock block = context;
    block(current, maximum);
}

static inline mailimap * get_imap_session(mailmessage * msg)
{
    return get_session_data(msg)->imap_session;
}


@implementation CTMIME_MessagePart
@synthesize data=mData;
@synthesize fetched=mFetched;
@synthesize lastError;

+ (id)mimeMessagePartWithContent:(CTMIME *)mime {
    return [[[CTMIME_MessagePart alloc] initWithContent:mime] autorelease];
}

- (id)initWithMIMEStruct:(struct mailmime *)mime 
              forMessage:(struct mailmessage *)message {
    self = [super initWithMIMEStruct:mime forMessage:message];
    if (self) {
        mMime = mime;
        mMessage = message;
        struct mailmime *content = mime->mm_data.mm_message.mm_msg_mime;
        myMessageContent = [[CTMIMEFactory createMIMEWithMIMEStruct:content
                                                         forMessage:message] retain];
        myFields = mime->mm_data.mm_message.mm_fields;
    }
    return self;
}

- (id)initWithContent:(CTMIME *)messageContent {
    self = [super init];
    if (self) {
        [self setContent:messageContent];
    }
    return self;
}

- (void)dealloc {
    [myMessageContent release];
    [super dealloc];
}

- (void)setContent:(CTMIME *)aContent {
    [aContent retain];
    [myMessageContent release];
    myMessageContent = aContent;
}

- (id)content {
    return myMessageContent;
}

- (struct mailmime *)buildMIMEStruct {
    struct mailmime *mime = mailmime_new_message_data([myMessageContent buildMIMEStruct]);
    if (myFields != NULL) {
        mailmime_set_imf_fields(mime, myFields);
    }
    return mime;
}

- (void)setIMFFields:(struct mailimf_fields *)imfFields {
    myFields = imfFields;
}

- (BOOL)fetchPartWithProgress:(CTProgressBlock)block {
    if (self.fetched == NO) {
        struct mailmime_single_fields *mimeFields = NULL;
        
        int encoding = MAILMIME_MECHANISM_8BIT;
        mimeFields = mailmime_single_fields_new(mMime->mm_mime_fields, mMime->mm_content_type);
        if (mimeFields != NULL && mimeFields->fld_encoding != NULL)
            encoding = mimeFields->fld_encoding->enc_type;
        
        char *fetchedData = NULL;
        size_t fetchedDataLen;
        int r;
        
        if (mMessage->msg_session != NULL) {
            mailimap_set_progress_callback(get_imap_session(mMessage), &download_progress_callback, NULL, block);
        }
        r = mailmessage_fetch_section_body(mMessage, mMime, &fetchedData, &fetchedDataLen);
        if (mMessage->msg_session != NULL) {
            mailimap_set_progress_callback(get_imap_session(mMessage), NULL, NULL, NULL);
        }
        if (r != MAIL_NO_ERROR) {
            if (fetchedData) {
                mailmessage_fetch_result_free(mMessage, fetchedData);
            }
            self.lastError = MailCoreCreateErrorFromIMAPCode(r);
            return NO;
        }
        
        
        size_t current_index = 0;
        char * result;
        size_t result_len;
        r = mailmime_part_parse(fetchedData, fetchedDataLen, &current_index,
                                encoding, &result, &result_len);
        if (r != MAILIMF_NO_ERROR) {
            mailmime_decoded_part_free(result);
            self.lastError = MailCoreCreateError(r, @"Error parsing the message");
            return NO;
        }
        NSData *data = [NSData dataWithBytes:result length:result_len];
        mailmessage_fetch_result_free(mMessage, fetchedData);
        mailmime_decoded_part_free(result);
        mailmime_single_fields_free(mimeFields);
        self.data = data;
        self.fetched = YES;
    }
    return YES;
}

- (BOOL)fetchPart {
    return [self fetchPartWithProgress:^(size_t curr, size_t max){}];
}

@end
