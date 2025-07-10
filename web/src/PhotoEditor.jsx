import React, { useEffect, useState } from 'react';
import { PhotoEditorSDKUI } from 'photoeditorsdk';

export const PhotoEditor = () => {
  const [editor, setEditor] = useState(null);
  const [exportedImageURL, setExportedImageURL] = useState('');
  const [selectedImage, setSelectedImage] = useState(null);
  const [isEditorInitialized, setIsEditorInitialized] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

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
        // Настройка кастомных стикеров
        sticker: {
          categories: [
            {
              identifier: 'custom_emoji',
              name: 'Emoji',
              items: [
                {
                  identifier: 'happy_face',
                  name: 'Happy Face',
                  thumbnailURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iNTAiIGN5PSI1MCIgcj0iNDAiIGZpbGw9IiNGRkMxMDciIHN0cm9rZT0iI0ZGOTgwMCIgc3Ryb2tlLXdpZHRoPSIyIi8+PGNpcmNsZSBjeD0iMzUiIGN5PSI0MCIgcj0iNCIgZmlsbD0iIzIxMjEyMSIvPjxjaXJjbGUgY3g9IjY1IiBjeT0iNDAiIHI9IjQiIGZpbGw9IiMyMTIxMjEiLz48cGF0aCBkPSJNIDMwIDYwIFEgNTAgNzUgNzAgNjAiIHN0cm9rZT0iIzIxMjEyMSIgc3Ryb2tlLXdpZHRoPSIzIiBmaWxsPSJub25lIiBzdHJva2UtbGluZWNhcD0icm91bmQiLz48L3N2Zz4=',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iNTAiIGN5PSI1MCIgcj0iNDAiIGZpbGw9IiNGRkMxMDciIHN0cm9rZT0iI0ZGOTgwMCIgc3Ryb2tlLXdpZHRoPSIyIi8+PGNpcmNsZSBjeD0iMzUiIGN5PSI0MCIgcj0iNCIgZmlsbD0iIzIxMjEyMSIvPjxjaXJjbGUgY3g9IjY1IiBjeT0iNDAiIHI9IjQiIGZpbGw9IiMyMTIxMjEiLz48cGF0aCBkPSJNIDMwIDYwIFEgNTAgNzUgNzAgNjAiIHN0cm9rZT0iIzIxMjEyMSIgc3Ryb2tlLXdpZHRoPSIzIiBmaWxsPSJub25lIiBzdHJva2UtbGluZWNhcD0icm91bmQiLz48L3N2Zz4='
                },
                {
                  identifier: 'sad_face',
                  name: 'Sad Face',
                  thumbnailURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iNTAiIGN5PSI1MCIgcj0iNDAiIGZpbGw9IiNGRkMxMDciIHN0cm9rZT0iI0ZGOTgwMCIgc3Ryb2tlLXdpZHRoPSIyIi8+PGNpcmNsZSBjeD0iMzUiIGN5PSI0MCIgcj0iNCIgZmlsbD0iIzIxMjEyMSIvPjxjaXJjbGUgY3g9IjY1IiBjeT0iNDAiIHI9IjQiIGZpbGw9IiMyMTIxMjEiLz48cGF0aCBkPSJNIDMwIDcwIFEgNTAgNTUgNzAgNzAiIHN0cm9rZT0iIzIxMjEyMSIgc3Ryb2tlLXdpZHRoPSIzIiBmaWxsPSJub25lIiBzdHJva2UtbGluZWNhcD0icm91bmQiLz48L3N2Zz4=',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iNTAiIGN5PSI1MCIgcj0iNDAiIGZpbGw9IiNGRkMxMDciIHN0cm9rZT0iI0ZGOTgwMCIgc3Ryb2tlLXdpZHRoPSIyIi8+PGNpcmNsZSBjeD0iMzUiIGN5PSI0MCIgcj0iNCIgZmlsbD0iIzIxMjEyMSIvPjxjaXJjbGUgY3g9IjY1IiBjeT0iNDAiIHI9IjQiIGZpbGw9IiMyMTIxMjEiLz48cGF0aCBkPSJNIDMwIDcwIFEgNTAgNTUgNzAgNzAiIHN0cm9rZT0iIzIxMjEyMSIgc3Ryb2tlLXdpZHRoPSIzIiBmaWxsPSJub25lIiBzdHJva2UtbGluZWNhcD0icm91bmQiLz48L3N2Zz4='
                },
                {
                  identifier: 'love_face',
                  name: 'Love Face',
                  thumbnailURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iNTAiIGN5PSI1MCIgcj0iNDAiIGZpbGw9IiNGRkMxMDciIHN0cm9rZT0iI0ZGOTgwMCIgc3Ryb2tlLXdpZHRoPSIyIi8+PHBhdGggZD0iTSAzMCAzNSBMIDMyIDMyIFEgMzUgMjkgMzggMzIgUSA0MSAyOSA0NCAzMiBMIDM1IDQ1IFoiIGZpbGw9IiNFOTFFNjMiLz48cGF0aCBkPSJNIDU2IDM1IEwgNTggMzIgUSA2MSAyOSA2NCAzMiBRIDY3IDI5IDcwIDMyIEwgNjEgNDUgWiIgZmlsbD0iI0U5MUU2MyIvPjxwYXRoIGQ9Ik0gMzAgNjAgUSA1MCA3NSA3MCA2MCIgc3Ryb2tlPSIjMjEyMTIxIiBzdHJva2Utd2lkdGg9IjMiIGZpbGw9Im5vbmUiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPjwvc3ZnPg==',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iNTAiIGN5PSI1MCIgcj0iNDAiIGZpbGw9IiNGRkMxMDciIHN0cm9rZT0iI0ZGOTgwMCIgc3Ryb2tlLXdpZHRoPSIyIi8+PHBhdGggZD0iTSAzMCAzNSBMIDMyIDMyIFEgMzUgMjkgMzggMzIgUSA0MSAyOSA0NCAzMiBMIDM1IDQ1IFoiIGZpbGw9IiNFOTFFNjMiLz48cGF0aCBkPSJNIDU2IDM1IEwgNTggMzIgUSA2MSAyOSA2NCAzMiBRIDY3IDI5IDcwIDMyIEwgNjEgNDUgWiIgZmlsbD0iI0U5MUU2MyIvPjxwYXRoIGQ9Ik0gMzAgNjAgUSA1MCA3NSA3MCA2MCIgc3Ryb2tlPSIjMjEyMTIxIiBzdHJva2Utd2lkdGg9IjMiIGZpbGw9Im5vbmUiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPjwvc3ZnPg=='
                },
                {
                  identifier: 'distance_control',
                  name: 'Distance Control',
                  thumbnailURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjYxIiBoZWlnaHQ9Ijc5IiB2aWV3Qm94PSIwIDAgMjYxIDc5IiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8cGF0aCBkPSJNNDEgMi41QzYyLjM1MTYgMi41IDc5LjUgMTkuMTUyNSA3OS41IDM5LjVDNzkuNSA1OS44NDc1IDYyLjM1MTYgNzYuNSA0MSA3Ni41QzE5LjY0ODQgNzYuNSAyLjUgNTkuODQ3NSAyLjUgMzkuNUMyLjUgMTkuMTUyNSAxOS42NDg0IDIuNSA0MSAyLjVaIiBzdHJva2U9ImJsYWNrIiBzdHJva2Utd2lkdGg9IjUiLz4KPGxpbmUgeDE9IjgyIiB5MT0iNDEuNSIgeDI9IjI1NiIgeTI9IjQxLjUiIHN0cm9rZT0iIzA5MDkwOSIgc3Ryb2tlLXdpZHRoPSI1Ii8+CjxsaW5lIHgxPSIyNTguNSIgeDI9IjI1OC41IiB5Mj0iNzkiIHN0cm9rZT0iYmxhY2siIHN0cm9rZS13aWR0aD0iNSIvPgo8L3N2Zz4K',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjYxIiBoZWlnaHQ9Ijc5IiB2aWV3Qm94PSIwIDAgMjYxIDc5IiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8cGF0aCBkPSJNNDEgMi41QzYyLjM1MTYgMi41IDc5LjUgMTkuMTUyNSA3OS41IDM5LjVDNzkuNSA1OS44NDc1IDYyLjM1MTYgNzYuNSA0MSA3Ni41QzE5LjY0ODQgNzYuNSAyLjUgNTkuODQ3NSAyLjUgMzkuNUMyLjUgMTkuMTUyNSAxOS42NDg0IDIuNSA0MSAyLjVaIiBzdHJva2U9ImJsYWNrIiBzdHJva2Utd2lkdGg9IjUiLz4KPGxpbmUgeDE9IjgyIiB5MT0iNDEuNSIgeDI9IjI1NiIgeTI9IjQxLjUiIHN0cm9rZT0iIzA5MDkwOSIgc3Ryb2tlLXdpZHRoPSI1Ii8+CjxsaW5lIHgxPSIyNTguNSIgeDI9IjI1OC41IiB5Mj0iNzkiIHN0cm9rZT0iYmxhY2siIHN0cm9rZS13aWR0aD0iNSIvPgo8L3N2Zz4K'
                },
                {
                  identifier: 'player',
                  name: 'Player',
                  thumbnailURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTE0IiBoZWlnaHQ9IjY2IiB2aWV3Qm94PSIwIDAgMTE0IDY2IiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8cGF0aCBkPSJNODQuODUyOCAxNi43MzY3QzEwMC44NjQgMjUuOTgwMSAxMDEuMzM5IDQwLjY5MjYgODUuOTEzNCA0OS41OTc4TDg1LjE4MzUgNTAuMDA4NUM2OS42OTQxIDU4LjQ5MjQgNDQuNzUyNyA1OC4wODQ2IDI4Ljk5MTIgNDguOTg1NkwyOC4yNTIxIDQ4LjU0ODFDMTMuMjExNSAzOS40MzA2IDEyLjc1NjggMjUuMzQ1OCAyNy4yMTk0IDE2LjU0NThMMjcuOTMwNyAxNi4xMjQ0QzQzLjM1NjQgNy4yMTkxOCA2OC44NDEzIDcuNDkzMjkgODQuODUyOCAxNi43MzY3Wk04MC41MjI2IDE5LjIzNjVDNjYuNzQ5IDExLjI4NTEgNDUuMTQ0NCAxMS4xODY2IDMyLjI2MDkgMTguNjI0M0MxOS4zNzc1IDI2LjA2MTkgMTkuNTQ4IDM4LjUzNDMgMzMuMzIxNSA0Ni40ODU3QzQ3LjA5NSA1NC40MzcyIDY4LjY5OTYgNTQuNTM1NiA4MS41ODMxIDQ3LjA5OEM5NC40NjY2IDM5LjY2MDQgOTQuMjk2MSAyNy4xODggODAuNTIyNiAxOS4yMzY1WiIgZmlsbD0iI0ZGMDAwMCIvPgo8L3N2Zz4K',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTE0IiBoZWlnaHQ9IjY2IiB2aWV3Qm94PSIwIDAgMTE0IDY2IiBmaWxsPSJub25lIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgo8cGF0aCBkPSJNODQuODUyOCAxNi43MzY3QzEwMC44NjQgMjUuOTgwMSAxMDEuMzM5IDQwLjY5MjYgODUuOTEzNCA0OS41OTc4TDg1LjE4MzUgNTAuMDA4NUM2OS42OTQxIDU4LjQ5MjQgNDQuNzUyNyA1OC4wODQ2IDI4Ljk5MTIgNDguOTg1NkwyOC4yNTIxIDQ4LjU0ODFDMTMuMjExNSAzOS40MzA2IDEyLjc1NjggMjUuMzQ1OCAyNy4yMTk0IDE2LjU0NThMMjcuOTMwNyAxNi4xMjQ0QzQzLjM1NjQgNy4yMTkxOCA2OC44NDEzIDcuNDkzMjkgODQuODUyOCAxNi43MzY3Wk04MC41MjI2IDE5LjIzNjVDNjYuNzQ5IDExLjI4NTEgNDUuMTQ0NCAxMS4xODY2IDMyLjI2MDkgMTguNjI0M0MxOS4zNzc1IDI2LjA2MTkgMTkuNTQ4IDM4LjUzNDMgMzMuMzIxNSA0Ni40ODU3QzQ3LjA5NSA1NC40MzcyIDY4LjY5OTYgNTQuNTM1NiA4MS41ODMxIDQ3LjA5OEM5NC40NjY2IDM5LjY2MDQgOTQuMjk2MSAyNy4xODggODAuNTIyNiAxOS4yMzY1WiIgZmlsbD0iI0ZGMDAwMCIvPgo8L3N2Zz4K'
                }
              ]
            },
            {
              identifier: 'custom_shapes',
              name: 'Shapes',
              items: [
                {
                  identifier: 'arrow_right',
                  name: 'Arrow Right',
                  thumbnailURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTSAyMCAzMCBMIDYwIDMwIEwgNjAgMjAgTCA4MCA1MCBMIDYwIDgwIEwgNjAgNzAgTCAyMCA3MCBaIiBmaWxsPSIjMjE5NkYzIiBzdHJva2U9IiMxOTc2RDIiIHN0cm9rZS13aWR0aD0iMSIvPjwvc3ZnPg==',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTSAyMCAzMCBMIDYwIDMwIEwgNjAgMjAgTCA4MCA1MCBMIDYwIDgwIEwgNjAgNzAgTCAyMCA3MCBaIiBmaWxsPSIjMjE5NkYzIiBzdHJva2U9IiMxOTc2RDIiIHN0cm9rZS13aWR0aD0iMSIvPjwvc3ZnPg=='
                },
                {
                  identifier: 'star',
                  name: 'Star',
                  thumbnailURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTSA1MCAxMCBMIDU5IDMyIEwgODMgMzIgTCA2NSA0NyBMIDc0IDY5IEwgNTAgNTQgTCAyNiA2OSBMIDM1IDQ3IEwgMTcgMzIgTCA0MSAzMiBaIiBmaWxsPSIjRkZENzAwIiBzdHJva2U9IiNGRkEwMDAiIHN0cm9rZS13aWR0aD0iMiIvPjwvc3ZnPg==',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTSA1MCAxMCBMIDU5IDMyIEwgODMgMzIgTCA2NSA0NyBMIDc0IDY5IEwgNTAgNTQgTCAyNiA2OSBMIDM1IDQ3IEwgMTcgMzIgTCA0MSAzMiBaIiBmaWxsPSIjRkZENzAwIiBzdHJva2U9IiNGRkEwMDAiIHN0cm9rZS13aWR0aD0iMiIvPjwvc3ZnPg=='
                },
                {
                  identifier: 'heart',
                  name: 'Heart',
                  thumbnailURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTSA1MCA4NSBDIDIwIDYwLCA1IDI1LCAyNSAxNSBDIDQwIDUsIDUwIDIwLCA1MCAyMCBDIDUwIDIwLCA2MCA1LCA3NSAxNSBDIDk1IDI1LCA4MCA2MCwgNTAgODUgWiIgZmlsbD0iI0U5MUU2MyIgc3Ryb2tlPSIjQzIxODVCIiBzdHJva2Utd2lkdGg9IjIiLz48L3N2Zz4=',
                  stickerURI: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgdmlld0JveD0iMCAwIDEwMCAxMDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTSA1MCA4NSBDIDIwIDYwLCA1IDI1LCAyNSAxNSBDIDQwIDUsIDUwIDIwLCA1MCAyMCBDIDUwIDIwLCA2MCA1LCA3NSAxNSBDIDk1IDI1LCA4MCA2MCwgNTAgODUgWiIgZmlsbD0iI0U5MUU2MyIgc3Ryb2tlPSIjQzIxODVCIiBzdHJva2Utd2lkdGg9IjIiLz48L3N2Zz4='
                }
              ]
            }
          ]
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

      console.log('PhotoEditor SDK инициализирован успешно');
      setEditor(editorInstance);
      setIsLoading(false);

      window.exportImage = exportImage;
    } catch (error) {
      console.error('Ошибка инициализации PhotoEditor SDK:', error);
      setIsLoading(false);
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

  const handleFileSelection = (event) => {
    const file = event.target.files[0];
    if (file && file.type.startsWith('image/')) {
      console.log('Файл выбран:', file.name, file.type, file.size);
      const reader = new FileReader();
      reader.onload = (e) => {
        const base64String = e.target.result;
        console.log('Base64 загружен, длина:', base64String.length);
        setSelectedImage(base64String);
        setIsEditorInitialized(true);
        setIsLoading(true);
        // Даем время на рендер перед инициализацией редактора
        setTimeout(() => {
          initEditor(base64String, false);
        }, 100);
      };
      reader.readAsDataURL(file);
    } else {
      console.error('Неверный тип файла');
    }
  };

  const resetEditor = () => {
    if (editor) {
      editor.dispose();
      setEditor(null);
    }
    setSelectedImage(null);
    setIsEditorInitialized(false);
    setIsLoading(false);
    setExportedImageURL('');
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

  // Если редактор не инициализирован, показываем экран выбора файла
  if (!isEditorInitialized) {
    return (
      <div style={{ 
        display: 'flex', 
        flexDirection: 'column', 
        alignItems: 'center', 
        justifyContent: 'center', 
        width: '100vw', 
        height: '100vh',
        backgroundColor: '#f5f5f5',
        fontFamily: 'Arial, sans-serif'
      }}>
        <div style={{
          backgroundColor: 'white',
          padding: '40px',
          borderRadius: '12px',
          boxShadow: '0 4px 12px rgba(0,0,0,0.1)',
          textAlign: 'center',
          maxWidth: '500px',
          width: '90%'
        }}>
          <h1 style={{ 
            marginBottom: '20px', 
            color: '#333',
            fontSize: '24px'
          }}>
            Photo Editor
          </h1>
          <p style={{ 
            marginBottom: '30px', 
            color: '#666',
            fontSize: '16px',
            lineHeight: '1.5'
          }}>
            Выберите изображение для редактирования
          </p>
          
          <input
            type="file"
            accept="image/*"
            onChange={handleFileSelection}
            style={{ display: 'none' }}
            id="fileInput"
          />
          
          <label
            htmlFor="fileInput"
            style={{
              display: 'inline-block',
              padding: '12px 24px',
              backgroundColor: '#4CAF50',
              color: 'white',
              borderRadius: '6px',
              cursor: 'pointer',
              fontSize: '16px',
              border: 'none',
              transition: 'background-color 0.3s'
            }}
            onMouseOver={(e) => e.target.style.backgroundColor = '#45a049'}
            onMouseOut={(e) => e.target.style.backgroundColor = '#4CAF50'}
          >
            Выбрать изображение
          </label>
          
          <div style={{ 
            marginTop: '20px', 
            fontSize: '14px', 
            color: '#888' 
          }}>
            Поддерживаемые форматы: JPG, PNG, GIF, WebP
          </div>
        </div>
      </div>
    );
  }

  return (
    <div style={{ position: 'relative', width: '100vw', height: '100vh' }}>
      {isLoading && (
        <div style={{
          position: 'absolute',
          top: 0,
          left: 0,
          width: '100%',
          height: '100%',
          backgroundColor: 'rgba(255, 255, 255, 0.9)',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 2000,
          fontSize: '18px',
          color: '#333'
        }}>
          <div style={{ marginBottom: '20px' }}>
            Загрузка редактора...
          </div>
          <div style={{
            width: '40px',
            height: '40px',
            border: '4px solid #f3f3f3',
            borderTop: '4px solid #4CAF50',
            borderRadius: '50%',
            animation: 'spin 1s linear infinite'
          }}></div>
        </div>
      )}
      
      <div id="editor" style={{ width: '100%', height: '100%' }}></div>
      
      {/* Кнопка для возврата к выбору файла */}
      <button
        onClick={resetEditor}
        style={{
          position: 'absolute',
          top: '10px',
          left: '10px',
          zIndex: 1000,
          padding: '8px 16px',
          backgroundColor: '#f44336',
          color: 'white',
          border: 'none',
          borderRadius: '4px',
          cursor: 'pointer',
          fontSize: '14px'
        }}
      >
        ← Выбрать другое фото
      </button>

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