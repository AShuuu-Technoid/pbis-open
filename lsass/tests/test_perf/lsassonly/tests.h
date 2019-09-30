/* Editor Settings: expandtabs and use 4 spaces for indentation
 * ex: set softtabstop=4 tabstop=8 expandtab shiftwidth=4: *
 * -*- mode: c, c-basic-offset: 4 -*- */

/*
 * Copyright © BeyondTrust Software 2004 - 2019
 * All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * BEYONDTRUST MAKES THIS SOFTWARE AVAILABLE UNDER OTHER LICENSING TERMS AS
 * WELL. IF YOU HAVE ENTERED INTO A SEPARATE LICENSE AGREEMENT WITH
 * BEYONDTRUST, THEN YOU MAY ELECT TO USE THE SOFTWARE UNDER THE TERMS OF THAT
 * SOFTWARE LICENSE AGREEMENT INSTEAD OF THE TERMS OF THE APACHE LICENSE,
 * NOTWITHSTANDING THE ABOVE NOTICE.  IF YOU HAVE QUESTIONS, OR WISH TO REQUEST
 * A COPY OF THE ALTERNATE LICENSING TERMS OFFERED BY BEYONDTRUST, PLEASE CONTACT
 * BEYONDTRUST AT beyondtrust.com/contact
 */

/*
 * Copyright (C) BeyondTrust Software. All rights reserved.
 *
 * Module Name:
 *
 *        tests.h
 *
 * Abstract:
 *
 *        BeyondTrust Security and Authentication Subsystem (LSASS) 
 *        
 *        Test helper function declarations
 *
 * Authors: Kyle Stemen <kstemen@likewisesoftware.com>
 *
 */

#ifndef LSASS_TESTS_H
#define LSASS_TESTS_H

#include "config.h"
#include <stdarg.h>
#if HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif
#include <lsa/lsa.h>
#include "lwmem.h"
#include "lwstr.h"
#include "lwsecurityidentifier.h"
#include <lsautils.h>

BOOL
RunConnectDisconnect(
    IN PVOID unused
    );

typedef struct _FIND_STATE
{
    uid_t Uid;
    HANDLE Connection;
} FIND_STATE;

BOOL
SetupFindUserById(
    IN PVOID username,
    OUT PVOID *ppvFindState
    );

BOOL
RunFindUserById(
    IN PVOID pvState
    );

void
CleanupFindUserById(
    IN PVOID pvState
    );

BOOL
SetupConnectLsass(
    IN PVOID username,
    OUT PVOID *pHandle
    );

BOOL
RunGetLogLevel(
    IN PVOID handle
    );

void
CleanupConnectLsass(
    IN PVOID handle
    );

#endif
