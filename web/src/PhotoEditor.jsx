import React, { useEffect, useState } from 'react';
import { PhotoEditorSDKUI } from 'photoeditorsdk';

export const PhotoEditor = () => {
  const [editor, setEditor] = useState(null);
  const [exportedImageURL, setExportedImageURL] = useState('');

  const initEditor = async (imageBase64, isDraw) => {
    try {
      const tools =  [
          ['brush'],
          ['transform', 'filter', 'adjustment'],
          ['focus', 'frame'],
          ['text', 'textdesign', 'sticker'],
        ];

      const editorInstance = await PhotoEditorSDKUI.init({
        container: '#editor',
        license: '{"api_token":"uaEQUr3GJk6FpZHSaXmlhS1VK66pSIggNiASsLMKGkNr400s0mTv8ay8Hu_fMk4_","app_identifiers":[],"available_actions":[],"domains":["https://api.photoeditorsdk.com"],"enterprise_license":false,"expires_at":1789812000,"features":["camera","library","export","customassets","whitelabel","adjustment","brush","filter","focus","frame","overlay","sticker","text","textdesign","transform"],"issued_at":1726747492,"minimum_sdk_version":"1.0","owner":"SMM Service","platform":"HTML5","products":["pesdk"],"version":"2.4","signature":"gSulxF/J1Z4ILO02Fa8CONA8SJAE7p+QxepQ/rVM7wFC6+/lqJ4rCN87DUKEnotBbaEEhjY76To17PZQGeegGL9KARhSCiYiAQz46BgX1wdNKvZ9joFxm0mhYTXgBOs1mZcFOMFck5Kl+hgT0eaVMCFoMsTkRdFa53A/2BfJSvvEvKhYQ8TxQD8NXTG191O5F8PIxI4d2vNwK/vTdGx3ZEtKAGVZYzQX2Bb3sR4ehEmhvCzgJ21RL75ydaTAbEI5qHRKHSXsohy+4UQUb2w7LtBo5w4hvgCZAsQ5wr+3Nj2akreRvQxJhxrQTXSZARNr6tB0exb4J5NmctKPCK0UGiFR11PCLBfJ3gO8jzTDKPgCMJlCFQxK4PoZmI0wkYLKr4DODQi2blfe7uTA82k79fEtE8gT1KP4dA8TTt98AItpq1ZAYvAKLxPgSyrmKZZQ0GWG357bENOl1MwsM3kSLKr6kip92kMqDI3fA/eJqQYZx+qtzniobYrBsy0nicULnkKH7szJJ3s25FsQOb473WXXQDEWdrMFUfniVyL0owhG777q2tSJFzNYw5GhtlSGpKBODguLEAELXlTwxXweihEYTbWZgHcFtgpfWEicTVte7QYPP6l/c76NGEgLJGXEeJs4qIhaCQRfeu0AYzEB2nw1U/D7B+OEIH/sI5CwKCM="}',
        image: imageBase64,
        language: 'en',
        assetBaseUrl:
          'https://cdn.img.ly/packages/imgly/photoeditorsdk/5.19.0/assets',
        layout: 'basic',
        mainCanvasActions: ['undo', 'redo'],
        tools,
        sticker: {
          categories: [
            {
              identifier: 'custom_stickers',
              name: 'Stickers',
              items: [
                {
                  identifier: 'select_player',
                  name: 'Select Player',
                  thumbnailURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTE0IiBoZWlnaHQ9IjY2IiB2aWV3Qm94PSIwIDAgMTE0IDY2IiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8cGF0aCBkPSJNODQuODUyOCAxNi43MzY3QzEwMC44NjQgMjUuOTgwMSAxMDEuMzM5IDQwLjY5MjYgODUuOTEzNCA0OS41OTc4TDg1LjE4MzUgNTAuMDA4NUM2OS42OTQxIDU4LjQ5MjQgNDQuNzUyNyA1OC4wODQ2IDI4Ljk5MTIgNDguOTg1NkwyOC4yNTIxIDQ4LjU0ODFDMTMuMjExNSAzOS40MzA2IDEyLjc1NjggMjUuMzQ1OCAyNy4yMTk0IDE2LjU0NThMMjcuOTMwNyAxNi4xMjQ0QzQzLjM1NjQgNy4yMTkxOCA2OC44NDEzIDcuNDkzMjkgODQuODUyOCAxNi43MzY3Wk04MC41MjI2IDE5LjIzNjVDNjYuNzQ5IDExLjI4NTEgNDUuMTQ0NCAxMS4xODY2IDMyLjI2MDkgMTguNjI0M0MxOS4zNzc1IDI2LjA2MTkgMTkuNTQ4IDM4LjUzNDMgMzMuMzIxNSA0Ni40ODU3QzQ3LjA5NSA1NC40MzcyIDY4LjY5OTYgNTQuNTM1NiA4MS41ODMxIDQ3LjA5OEM5NC40NjY2IDM5LjY2MDQgOTQuMjk2MSAyNy4xODggODAuNTIyNiAxOS4yMzY1WiIgZmlsbD0iI0ZGMDAwMCIvPgo8L3N2Zz4K',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTE0IiBoZWlnaHQ9IjY2IiB2aWV3Qm94PSIwIDAgMTE0IDY2IiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8cGF0aCBkPSJNODQuODUyOCAxNi43MzY3QzEwMC44NjQgMjUuOTgwMSAxMDEuMzM5IDQwLjY5MjYgODUuOTEzNCA0OS41OTc4TDg1LjE4MzUgNTAuMDA4NUM2OS42OTQxIDU4LjQ5MjQgNDQuNzUyNyA1OC4wODQ2IDI4Ljk5MTIgNDguOTg1NkwyOC4yNTIxIDQ4LjU0ODFDMTMuMjExNSAzOS40MzA2IDEyLjc1NjggMjUuMzQ1OCAyNy4yMTk0IDE2LjU0NThMMjcuOTMwNyAxNi4xMjQ0QzQzLjM1NjQgNy4yMTkxOCA2OC44NDEzIDcuNDkzMjkgODQuODUyOCAxNi43MzY3Wk04MC41MjI2IDE5LjIzNjVDNjYuNzQ5IDExLjI4NTEgNDUuMTQ0NCAxMS4xODY2IDMyLjI2MDkgMTguNjI0M0MxOS4zNzc1IDI2LjA2MTkgMTkuNTQ4IDM4LjUzNDMgMzMuMzIxNSA0Ni40ODU3QzQ3LjA5NSA1NC40MzcyIDY4LjY5OTYgNTQuNTM1NiA4MS41ODMxIDQ3LjA5OEM5NC40NjY2IDM5LjY2MDQgOTQuMjk2MSAyNy4xODggODAuNTIyNiAxOS4yMzY1WiIgZmlsbD0iI0ZGMDAwMCIvPgo8L3N2Zz4K'
                },
                {
                  identifier: 'select_player_left',
                  name: 'Select Player Left',
                  thumbnailURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTYyIiBoZWlnaHQ9Ijk0IiB2aWV3Qm94PSIwIDAgMTYyIDk0IiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8bWFzayBpZD0icGF0aC0xLWluc2lkZS0xXzdfMTEiIGZpbGw9IndoaXRlIj4KPHBhdGggZD0iTTkyLjQ2NDUgMTQuNDczNEMxMDIuNDY1IDE1LjgwMTkgMTExLjcwOSAxOC42NTI2IDExOS4yMjkgMjIuNzI2OEMxMjYuNzQ5IDI2LjgwMTEgMTMyLjI2NyAzMS45NDg5IDEzNS4yMDYgMzcuNjMwOEMxMzguMTQ1IDQzLjMxMjcgMTM4LjM5NyA0OS4zMTk3IDEzNS45MzQgNTUuMDIyMkMxMzMuNDcxIDYwLjcyNDggMTI4LjM4NSA2NS45MTMgMTIxLjIwOCA3MC4wNDM0QzExNC4wMzIgNzQuMTczNyAxMDUuMDI5IDc3LjA5NCA5NS4xNDI5IDc4LjQ5ODVDODUuMjU3IDc5LjkwMjkgNzQuODUyIDc5LjczOTYgNjUuMDE4MiA3OC4wMjU4QzU1LjE4NDMgNzYuMzEyMSA0Ni4yODM2IDczLjExMDggMzkuMjQ4NiA2OC43NTc1QzMyLjIxMzYgNjQuNDA0MyAyNy4zMDMzIDU5LjA1OTIgMjUuMDMyMiA1My4yODI0TDM0LjE2NDcgNTIuMTczOUMzNi4wNjI2IDU3LjAwMTQgNDAuMTY2IDYxLjQ2ODIgNDYuMDQ1MSA2NS4xMDYyQzUxLjkyNDEgNjguNzQ0MiA1OS4zNjIzIDcxLjQxOTQgNjcuNTgwMiA3Mi44NTE2Qzc1Ljc5ODIgNzQuMjgzNyA4NC40OTM1IDc0LjQyMDEgOTIuNzU0OSA3My4yNDY1QzEwMS4wMTYgNzIuMDcyOSAxMDguNTQgNjkuNjMyNCAxMTQuNTM3IDY2LjE4MDdDMTIwLjUzNSA2Mi43MjkxIDEyNC43ODUgNTguMzkzNCAxMjYuODQzIDUzLjYyNzhDMTI4LjkwMSA0OC44NjIzIDEyOC42OTEgNDMuODQyNCAxMjYuMjM1IDM5LjA5NDFDMTIzLjc3OSAzNC4zNDU4IDExOS4xNjcgMzAuMDQzOSAxMTIuODgzIDI2LjYzOTFDMTA2LjU5OSAyMy4yMzQ0IDk4Ljg3MzcgMjAuODUyMSA5MC41MTY2IDE5Ljc0MTlMOTIuNDY0NSAxNC40NzM0WiIvPgo8L21hc2s+CjxwYXRoIGQ9Ik05Mi40NjQ1IDE0LjQ3MzRDMTAyLjQ2NSAxNS44MDE5IDExMS43MDkgMTguNjUyNiAxMTkuMjI5IDIyLjcyNjhDMTI2Ljc0OSAyNi44MDExIDEzMi4yNjcgMzEuOTQ4OSAxMzUuMjA2IDM3LjYzMDhDMTM4LjE0NSA0My4zMTI3IDEzOC4zOTcgNDkuMzE5NyAxMzUuOTM0IDU1LjAyMjJDMTMzLjQ3MSA2MC43MjQ4IDEyOC4zODUgNjUuOTEzIDEyMS4yMDggNzAuMDQzNEMxMTQuMDMyIDc0LjE3MzcgMTA1LjAyOSA3Ny4wOTQgOTUuMTQyOSA3OC40OTg1Qzg1LjI1NyA3OS45MDI5IDc0Ljg1MiA3OS43Mzk2IDY1LjAxODIgNzguMDI1OEM1NS4xODQzIDc2LjMxMjEgNDYuMjgzNiA3My4xMTA4IDM5LjI0ODYgNjguNzU3NUMzMi4yMTM2IDY0LjQwNDMgMjcuMzAzMyA1OS4wNTkyIDI1LjAzMjIgNTMuMjgyNEwzNC4xNjQ3IDUyLjE3MzlDMzYuMDYyNiA1Ny4wMDE0IDQwLjE2NiA2MS40NjgyIDQ2LjA0NTEgNjUuMTA2MkM1MS45MjQxIDY4Ljc0NDIgNTkuMzYyMyA3MS40MTk0IDY3LjU4MDIgNzIuODUxNkM3NS43OTgyIDc0LjI4MzcgODQuNDkzNSA3NC40MjAxIDkyLjc1NDkgNzMuMjQ2NUMxMDEuMDE2IDcyLjA3MjkgMTA4LjU0IDY5LjYzMjQgMTE0LjUzNyA2Ni4xODA3QzEyMC41MzUgNjIuNzI5MSAxMjQuNzg1IDU4LjM5MzQgMTI2Ljg0MyA1My42Mjc4QzEyOC45MDEgNDguODYyMyAxMjguNjkxIDQzLjg0MjQgMTI2LjIzNSAzOS4wOTQxQzEyMy43NzkgMzQuMzQ1OCAxMTkuMTY3IDMwLjA0MzkgMTEyLjg4MyAyNi42MzkxQzEwNi41OTkgMjMuMjM0NCA5OC44NzM3IDIwLjg1MjEgOTAuNTE2NiAxOS43NDE5TDkyLjQ2NDUgMTQuNDczNFoiIGZpbGw9IiNFMTAwMDAiIHN0cm9rZT0iYmxhY2siIHN0cm9rZS13aWR0aD0iMiIgbWFzaz0idXJsKCNwYXRoLTEtaW5zaWRlLTFfN18xMSkiLz4KPC9zdmc+Cg==',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTYyIiBoZWlnaHQ9Ijk0IiB2aWV3Qm94PSIwIDAgMTYyIDk0IiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8bWFzayBpZD0icGF0aC0xLWluc2lkZS0xXzdfMTEiIGZpbGw9IndoaXRlIj4KPHBhdGggZD0iTTkyLjQ2NDUgMTQuNDczNEMxMDIuNDY1IDE1LjgwMTkgMTExLjcwOSAxOC42NTI2IDExOS4yMjkgMjIuNzI2OEMxMjYuNzQ5IDI2LjgwMTEgMTMyLjI2NyAzMS45NDg5IDEzNS4yMDYgMzcuNjMwOEMxMzguMTQ1IDQzLjMxMjcgMTM4LjM5NyA0OS4zMTk3IDEzNS45MzQgNTUuMDIyMkMxMzMuNDcxIDYwLjcyNDggMTI4LjM4NSA2NS45MTMgMTIxLjIwOCA3MC4wNDM0QzExNC4wMzIgNzQuMTczNyAxMDUuMDI5IDc3LjA5NCA5NS4xNDI5IDc4LjQ5ODVDODUuMjU3IDc5LjkwMjkgNzQuODUyIDc5LjczOTYgNjUuMDE4MiA3OC4wMjU4QzU1LjE4NDMgNzYuMzEyMSA0Ni4yODM2IDczLjExMDggMzkuMjQ4NiA2OC43NTc1QzMyLjIxMzYgNjQuNDA0MyAyNy4zMDMzIDU5LjA1OTIgMjUuMDMyMiA1My4yODI0TDM0LjE2NDcgNTIuMTczOUMzNi4wNjI2IDU3LjAwMTQgNDAuMTY2IDYxLjQ2ODIgNDYuMDQ1MSA2NS4xMDYyQzUxLjkyNDEgNjguNzQ0MiA1OS4zNjIzIDcxLjQxOTQgNjcuNTgwMiA3Mi44NTE2Qzc1Ljc5ODIgNzQuMjgzNyA4NC40OTM1IDc0LjQyMDEgOTIuNzU0OSA3My4yNDY1QzEwMS4wMTYgNzIuMDcyOSAxMDguNTQgNjkuNjMyNCAxMTQuNTM3IDY2LjE4MDdDMTIwLjUzNSA2Mi43MjkxIDEyNC43ODUgNTguMzkzNCAxMjYuODQzIDUzLjYyNzhDMTI4LjkwMSA0OC44NjIzIDEyOC42OTEgNDMuODQyNCAxMjYuMjM1IDM5LjA5NDFDMTIzLjc3OSAzNC4zNDU4IDExOS4xNjcgMzAuMDQzOSAxMTIuODgzIDI2LjYzOTFDMTA2LjU5OSAyMy4yMzQ0IDk4Ljg3MzcgMjAuODUyMSA5MC41MTY2IDE5Ljc0MTlMOTIuNDY0NSAxNC40NzM0WiIvPgo8L21hc2s+CjxwYXRoIGQ9Ik05Mi40NjQ1IDE0LjQ3MzRDMTAyLjQ2NSAxNS44MDE5IDExMS43MDkgMTguNjUyNiAxMTkuMjI5IDIyLjcyNjhDMTI2Ljc0OSAyNi44MDExIDEzMi4yNjcgMzEuOTQ4OSAxMzUuMjA2IDM3LjYzMDhDMTM4LjE0NSA0My4zMTI3IDEzOC4zOTcgNDkuMzE5NyAxMzUuOTM0IDU1LjAyMjJDMTMzLjQ3MSA2MC43MjQ4IDEyOC4zODUgNjUuOTEzIDEyMS4yMDggNzAuMDQzNEMxMTQuMDMyIDc0LjE3MzcgMTA1LjAyOSA3Ny4wOTQgOTUuMTQyOSA3OC40OTg1Qzg1LjI1NyA3OS45MDI5IDc0Ljg1MiA3OS43Mzk2IDY1LjAxODIgNzguMDI1OEM1NS4xODQzIDc2LjMxMjEgNDYuMjgzNiA3My4xMTA4IDM5LjI0ODYgNjguNzU3NUMzMi4yMTM2IDY0LjQwNDMgMjcuMzAzMyA1OS4wNTkyIDI1LjAzMjIgNTMuMjgyNEwzNC4xNjQ3IDUyLjE3MzlDMzYuMDYyNiA1Ny4wMDE0IDQwLjE2NiA2MS40NjgyIDQ2LjA0NTEgNjUuMTA2MkM1MS45MjQxIDY4Ljc0NDIgNTkuMzYyMyA3MS40MTk0IDY3LjU4MDIgNzIuODUxNkM3NS43OTgyIDc0LjI4MzcgODQuNDkzNSA3NC40MjAxIDkyLjc1NDkgNzMuMjQ2NUMxMDEuMDE2IDcyLjA3MjkgMTA4LjU0IDY5LjYzMjQgMTE0LjUzNyA2Ni4xODA3QzEyMC41MzUgNjIuNzI5MSAxMjQuNzg1IDU4LjM5MzQgMTI2Ljg0MyA1My42Mjc4QzEyOC45MDEgNDguODYyMyAxMjguNjkxIDQzLjg0MjQgMTI2LjIzNSAzOS4wOTQxQzEyMy43NzkgMzQuMzQ1OCAxMTkuMTY3IDMwLjA0MzkgMTEyLjg4MyAyNi42MzkxQzEwNi41OTkgMjMuMjM0NCA5OC44NzM3IDIwLjg1MjEgOTAuNTE2NiAxOS43NDE5TDkyLjQ2NDUgMTQuNDczNFoiIGZpbGw9IiNFMTAwMDAiIHN0cm9rZT0iYmxhY2siIHN0cm9rZS13aWR0aD0iMiIgbWFzaz0idXJsKCNwYXRoLTEtaW5zaWRlLTFfN18xMSkiLz4KPC9zdmc+Cg=='
                },
                {
                  identifier: 'distance_control',
                  name: 'Distance Control',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjYxIiBoZWlnaHQ9Ijc5IiB2aWV3Qm94PSIwIDAgMjYxIDc5IiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8cGF0aCBkPSJNNDEgMi41QzYyLjM1MTYgMi41IDc5LjUgMTkuMTUyNSA3OS41IDM5LjVDNzkuNSA1OS44NDc1IDYyLjM1MTYgNzYuNSA0MSA3Ni41QzE5LjY0ODQgNzYuNSAyLjUgNTkuODQ3NSAyLjUgMzkuNUMyLjUgMTkuMTUyNSAxOS42NDg0IDIuNSA0MSAyLjVaIiBzdHJva2U9ImJsYWNrIiBzdHJva2Utd2lkdGg9IjUiLz4KPGxpbmUgeDE9IjgyIiB5MT0iNDEuNSIgeDI9IjI1NiIgeTI9IjQxLjUiIHN0cm9rZT0iIzA5MDkwOSIgc3Ryb2tlLXdpZHRoPSI1Ii8+CjxsaW5lIHgxPSIyNTguNSIgeDI9IjI1OC41IiB5Mj0iNzkiIHN0cm9rZT0iYmxhY2siIHN0cm9rZS13aWR0aD0iNSIvPgo8L3N2Zz4K'
                }
              ]
            }
          ],
        },
        brush: {
          colors: [
            { color: [1.00, 1.00, 1.00, 1], name: "white" },
            { color: [0.49, 0.49, 0.49, 1], name: "gray" },
            { color: [0.00, 0.00, 0.00, 1], name: "black" },
            { color: [0.40, 0.80, 1.00, 1], name: "light blue" },
            { color: [0.40, 0.53, 1.00, 1], name: "blue" },
            { color: [0.53, 0.40, 1.00, 1], name: "purple" },
            { color: [0.87, 0.40, 1.00, 1], name: "orchid" },
            { color: [1.00, 0.40, 0.80, 1], name: "pink" },
            { color: [0.90, 0.31, 0.31, 1], name: "red" },
            { color: [0.95, 0.53, 0.33, 1], name: "orange" },
            { color: [1.00, 0.80, 0.40, 1], name: "gold" },
            { color: [1.00, 0.97, 0.39, 1], name: "yellow" },
            { color: [0.80, 1.00, 0.40, 1], name: "olive" },
            { color: [0.33, 1.00, 0.53, 1], name: "green" },
            { color: [0.33, 1.00, 0.92, 1], name: "aquamarine" },
            { color: [0.75, 0.22, 0.17, 1], name: "crimson" },
            { color: [0.99, 0.50, 0.44, 1], name: "coral" },
            { color: [0.98, 0.92, 0.84, 1], name: "beige" },
            { color: [0.62, 0.32, 0.17, 1], name: "brown" },
            { color: [0.74, 0.72, 0.42, 1], name: "khaki" },
            { color: [0.54, 0.17, 0.89, 1], name: "violet" },
            { color: [0.72, 0.45, 0.20, 1], name: "sienna" },
            { color: [0.36, 0.20, 0.09, 1], name: "chocolate" },
            { color: [0.50, 0.50, 0.00, 1], name: "olive drab" },
            { color: [0.33, 0.42, 0.18, 1], name: "dark olive green" },
            { color: [0.11, 0.56, 0.56, 1], name: "cadet blue" },
            { color: [0.18, 0.31, 0.31, 1], name: "teal" },
            { color: [0.65, 0.74, 0.86, 1], name: "slate gray" },
            { color: [0.53, 0.81, 0.92, 1], name: "sky blue" },
            { color: [0.72, 0.53, 0.04, 1], name: "bronze" }
          ]
        },
      });

      setEditor(editorInstance);

      window.exportImage = exportImage;
    } catch (error) {
      console.error('Error initializing PhotoEditorSDKUI:', error);
    }
  };

  const exportImage = () => {
    if (!editor) {
      sendImageToNativeApp('');
      return;
    }


    editor
      .export({
        format: 'image/jpeg',
        exportType: 'data-url',
        quality: 1.0,
        enableDownload: false,
        preventExportEvent: true,
      })
      .then(function (dataURL) {
        var base64String = dataURL.split(',')[1];
        setExportedImageURL(dataURL);
        sendImageToNativeApp(base64String);
      })
      .catch(function (err) {
        sendImageToNativeApp('');
      });
  };

  const sendImageToNativeApp = (base64String) => {
    try {
      window.webkit.messageHandlers.imageExport.postMessage(base64String);
    } catch (error) {
      console.error('Error sending image to native app:', error);
    }
  };

  useEffect(() => {
    const handleMessage = (event) => {
      if (event.data.type === 'initEditor') {
        initEditor(event.data.imageBase64, event.data.isDraw);
      }
      if (event.data.type === 'updateEditor') {
        if (editor) {
          const image = new Image();
          image.onload = function () {
            editor.setImage(image);
          };
          image.src = event.data.imageBase64;
        }
      }
    };

    window.addEventListener('message', handleMessage);

    return () => {
      window.removeEventListener('message', handleMessage);
    };
  }, [editor]);

  return (
    <div style={{ position: 'relative', width: '100vw', height: '100vh' }}>
      <div id="editor" style={{ width: '100%', height: '100%' }}></div>
      <button
        id="exportButton"
        onClick={exportImage}
        style={{
          position: 'absolute',
          top: '0px',
          right: '0px',
          zIndex: 1000,
          fontSize: '0px',
          backgroundColor: exportedImageURL ? 'red' : '#4CAF50',
          color: 'white',
          border: 'none',
          cursor: 'pointer',
          opacity: '0.0'
        }}
      >
        {exportedImageURL ? (
          <a
            href={exportedImageURL}
            target="_blank"
            rel="noopener noreferrer"
            style={{ color: 'white', textDecoration: 'none' }}
          >
          </a>
        ) : (
          'Export Image'
        )}
      </button>
    </div>
  );
};