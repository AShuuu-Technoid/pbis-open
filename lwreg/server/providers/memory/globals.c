/* Editor Settings: expandtabs and use 4 spaces for indentation
 * ex: set softtabstop=4 tabstop=8 expandtab shiftwidth=4: *
 */

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
 *        globals.c
 *
 * Abstract:
 *        Global Variables for registry memory provider backend
 *
 * Authors: Adam Bernstein (abernstein@likewise.com)
 */
#include "includes.h"

static PREG_DB_CONNECTION gMemRegRoot;

inline
PREG_DB_CONNECTION 
MemRegRoot(
    VOID)
{
    return gMemRegRoot;
}

inline VOID
MemRegRootInit(
    PREG_DB_CONNECTION hMemRegRoot
    )
{
    gMemRegRoot = hMemRegRoot;
}


REGPROV_PROVIDER_FUNCTION_TABLE gRegMemProviderAPITable =
{
        &MemCreateKeyEx,
        &MemCloseKey,
        &MemDeleteKey,
        &MemDeleteKeyValue,
        &MemDeleteValue,
        &MemDeleteTree,
        &MemEnumKeyEx,
        &MemEnumValue,
        &MemGetValue,
        &MemOpenKeyEx,
        &MemQueryInfoKey,
        &MemQueryMultipleValues,
        &MemSetValueEx,
        &MemSetKeySecurity,
        &MemGetKeySecurity,
        &MemSetValueAttributes,
        &MemGetValueAttributes,
        &MemDeleteValueAttributes
};


/*
local variables:
mode: c
c-basic-offset: 4
indent-tabs-mode: nil
tab-width: 4
end:
*/
