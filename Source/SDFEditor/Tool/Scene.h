// Copyright (c) 2022 David Gallardo and SDFEditor Project

#pragma once

#include <cstdint>
#include <vector>
#include <memory>


#include <SDFEditor/Tool/StrokeInfo.h>
#include <SDFEditor/Tool/SceneStack.h>
#include <SDFEditor/Tool/SceneClipboard.h>
#include <SDFEditor/Tool/SceneDocument.h>

#include <SDFEditor/Tool/Camera.h>



class CScene
{
public:
    CScene();
    ~CScene();

    CScene(const CScene&) = delete;
    CScene(const CScene&&) = delete;
    
    void Reset(bool aAddDefault);

    bool IsDirty() const { return mDirty; }
    void SetDirty();
    void CleanDirtyFlag() { mDirty = false; }

    bool IsMaterialDirty() const { return mMaterialDirty; }
    void SetMaterialDirty();
    void CleanMaterialDirtyFlag() { mMaterialDirty = false; }

    uint32_t AddNewStroke(uint32_t aBaseStrokeIndex = UINT32_MAX);

    // Scene data
    std::vector< TStrokeInfo > mStrokesArray;
    std::vector<uint32_t> mSelectedItems;
    CCamera mCamera;
    TGlobalMaterialBufferData mGlobalMaterial;

    // Components
    std::unique_ptr<CSceneStack> mStack;
    std::unique_ptr<CSceneClipboard> mClipboard;
    std::unique_ptr<CSceneDocument> mDocument;

    // Debug
    int32_t mPreviewSlice{ 64 };
    bool    mUseVoxels{ true };
    bool    mLutNearestFilter{ false };
    bool    mAtlasNearestFilter{ false };
private:
    bool mDirty;
    bool mMaterialDirty;
    uint32_t mNextStrokeId;
};

