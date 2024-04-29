/**
 * Copyright (c) 2024, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 Inc. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import { Stack } from "@mui/material"
import StarRate from "@mui/icons-material/StarRate"

export default function LikeCount({ count, limit }) {
    let stars = [];

    for (let starCount = 0; starCount < limit; starCount++) {
        if (starCount < count) {
            stars.push(<StarRate color="primary" key={starCount} sx={{ fontSize: "1rem" }} />)
        } else {
            stars.push(<StarRate color="secondary" key={starCount} sx={{ fontSize: "1rem" }} />)
        }
    }

    return (
        <Stack direction="row" gap="0.1rem">
            {stars}
        </Stack>
    )
}
